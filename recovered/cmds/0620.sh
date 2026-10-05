cd /tmp/scratch/app/src; cat > render.rs <<'EOF'
//! Background page renderer. One worker thread owns its own copy of every open document
//! (MuPDF documents are not Send), renders tiles and low-res page bases into RGBA buffers,
//! and the UI thread only uploads finished buffers as textures.
use mupdf::pdf::PdfDocument;
use mupdf::{Colorspace, Device, DisplayList, IRect, Matrix, Pixmap};
use std::collections::HashMap;
use std::sync::mpsc::{channel, Receiver, Sender, TryRecvError};
use std::sync::{Arc, Mutex};
use std::time::Instant;

pub const TILE: i32 = 1024;
pub const BASE_SIDE: f32 = 700.0;

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Kind { Base, Tile { key: u32, tx: u16, ty: u16 } }
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Job { pub tab: u32, pub epoch: u32, pub page: usize, pub kind: Kind }

pub enum Src { Path(String), Bytes(Vec<u8>) }
pub enum Cmd {
    Open { tab: u32, epoch: u32, rev: u32, src: Src, pw: Option<String>, want_sizes: bool },
    Close { tab: u32 },
    Want(Vec<Job>),
}
pub enum Res {
    Sizes { tab: u32, epoch: u32, sizes: Vec<(f32, f32)> },
    Img { job: Job, rev: u32, w: usize, h: usize, rgba: Vec<u8>, ms: f32 },
    Failed { tab: u32, epoch: u32, msg: String },
}

pub struct Worker { pub tx: Sender<Cmd>, pub rx: Receiver<Res>, pub ctx: Arc<Mutex<Option<egui::Context>>> }

impl Worker {
    pub fn new() -> Worker {
        let (ctx_tx, ctx_rx) = channel::<Cmd>();
        let (res_tx, res_rx) = channel::<Res>();
        let ctx: Arc<Mutex<Option<egui::Context>>> = Arc::new(Mutex::new(None));
        let c2 = ctx.clone();
        let _ = std::thread::Builder::new().name("render".into()).stack_size(32 << 20).spawn(move || run(ctx_rx, res_tx, c2));
        Worker { tx: ctx_tx, rx: res_rx, ctx }
    }
}

struct Doc { doc: PdfDocument, epoch: u32, rev: u32, lists: Vec<(usize, DisplayList)> }

fn wake(ctx: &Arc<Mutex<Option<egui::Context>>>) { if let Ok(g) = ctx.lock() { if let Some(c) = g.as_ref() { c.request_repaint(); } } }

fn run(rx: Receiver<Cmd>, tx: Sender<Res>, ctx: Arc<Mutex<Option<egui::Context>>>) {
    let mut docs: HashMap<u32, Doc> = HashMap::new();
    let mut want: Vec<Job> = vec![];
    let mut done_since_want: std::collections::HashSet<Job> = Default::default();
    loop {
        // take every pending command first so a stale queue never delays fresh work
        let mut cmds = vec![];
        loop { match rx.try_recv() { Ok(c) => cmds.push(c), Err(TryRecvError::Empty) => break, Err(TryRecvError::Disconnected) => return } }
        if cmds.is_empty() && want.is_empty() { match rx.recv() { Ok(c) => cmds.push(c), Err(_) => return } }
        for c in cmds {
            match c {
                Cmd::Want(w) => { want = w; done_since_want.clear(); }
                Cmd::Close { tab } => { docs.remove(&tab); want.retain(|j| j.tab != tab); }
                Cmd::Open { tab, epoch, rev, src, pw, want_sizes } => {
                    let r = (|| -> Result<PdfDocument, String> {
                        let mut d = match src {
                            Src::Path(p) => { let b = std::fs::read(&p).map_err(|e| e.to_string())?; PdfDocument::from_bytes(&b).map_err(|e| e.to_string())? }
                            Src::Bytes(b) => PdfDocument::from_bytes(&b).map_err(|e| e.to_string())?,
                        };
                        if d.needs_password().unwrap_or(false) { if !d.authenticate(pw.as_deref().unwrap_or("")).unwrap_or(false) { return Err("password".into()); } }
                        Ok(d)
                    })();
                    match r {
                        Ok(d) => {
                            if want_sizes { let n = d.page_count().unwrap_or(0); let sizes: Vec<(f32, f32)> = (0..n).map(|i| d.load_page(i).ok().and_then(|p| p.bounds().ok()).map(|b| (b.x1 - b.x0, b.y1 - b.y0)).unwrap_or((595.0, 842.0))).collect(); let _ = tx.send(Res::Sizes { tab, epoch, sizes }); }
                            docs.insert(tab, Doc { doc: d, epoch, rev, lists: vec![] });
                        }
                        Err(m) => { let _ = tx.send(Res::Failed { tab, epoch, msg: m }); }
                    }
                    wake(&ctx);
                }
            }
        }
        if want.is_empty() { continue; }
        let job = want.remove(0);
        if done_since_want.contains(&job) { continue; }
        let Some(d) = docs.get_mut(&job.tab) else { continue };
        if d.epoch != job.epoch { continue; }
        let t = Instant::now();
        if let Some((w, h, rgba)) = render_job(d, &job) {
            done_since_want.insert(job);
            let _ = tx.send(Res::Img { job, rev: d.rev, w, h, rgba, ms: t.elapsed().as_secs_f32() * 1000.0 });
            wake(&ctx);
        }
    }
}

/// Pixel size of a page at scale `s` (pixels per point).
pub fn page_px(sz: (f32, f32), s: f32) -> (i32, i32) { (((sz.0 * s).ceil() as i32).max(1), ((sz.1 * s).ceil() as i32).max(1)) }
pub fn key_scale(key: u32) -> f32 { key as f32 / 256.0 }
pub fn scale_key(s: f32) -> u32 { ((s * 256.0).round() as u32).max(1) }

fn list_for<'a>(d: &'a mut Doc, page: usize) -> Option<&'a DisplayList> {
    if let Some(i) = d.lists.iter().position(|(p, _)| *p == page) { let e = d.lists.remove(i); d.lists.push(e); }
    else {
        let pg = d.doc.load_page(page as i32).ok()?;
        let l = pg.to_display_list(true).ok()?;
        d.lists.push((page, l));
        if d.lists.len() > 6 { d.lists.remove(0); }
    }
    d.lists.last().map(|(_, l)| l)
}

/// Render one job to RGBA. Tiles are cut from the same display list so neighbours match to the pixel.
pub fn render_job_doc(doc: &PdfDocument, list: &DisplayList, size: (f32, f32), kind: Kind) -> Option<(usize, usize, Vec<u8>)> {
    let _ = doc;
    let (scale, rect) = match kind {
        Kind::Base => { let s = (BASE_SIDE / size.0.max(size.1).max(1.0)).min(2.0); let (w, h) = page_px(size, s); (s, IRect { x0: 0, y0: 0, x1: w, y1: h }) }
        Kind::Tile { key, tx, ty } => {
            let s = key_scale(key); let (w, h) = page_px(size, s);
            let x0 = tx as i32 * TILE; let y0 = ty as i32 * TILE;
            if x0 >= w || y0 >= h { return None; }
            (s, IRect { x0, y0, x1: (x0 + TILE).min(w), y1: (y0 + TILE).min(h) })
        }
    };
    let mut pm = Pixmap::new_with_rect(&Colorspace::device_rgb(), rect, true).ok()?;
    pm.clear_with(255).ok()?;
    {
        let dev = Device::from_pixmap(&pm).ok()?;
        let ctm = Matrix::new_scale(scale, scale);
        let area = mupdf::Rect { x0: rect.x0 as f32 / scale - 1.0, y0: rect.y0 as f32 / scale - 1.0, x1: rect.x1 as f32 / scale + 1.0, y1: rect.y1 as f32 / scale + 1.0 };
        list.run(&dev, &ctm, area).ok()?;
    }
    let (w, h) = ((rect.x1 - rect.x0) as usize, (rect.y1 - rect.y0) as usize);
    let n = pm.n() as usize; let st = pm.stride() as usize;
    let s = pm.samples();
    if n != 4 { return None; }
    let mut out = Vec::with_capacity(w * h * 4);
    if st == w * 4 { out.extend_from_slice(&s[..w * h * 4]); } else { for y in 0..h { out.extend_from_slice(&s[y * st..y * st + w * 4]); } }
    Some((w, h, out))
}

fn render_job(d: &mut Doc, job: &Job) -> Option<(usize, usize, Vec<u8>)> {
    let size = { let pg = d.doc.load_page(job.page as i32).ok()?; let b = pg.bounds().ok()?; (b.x1 - b.x0, b.y1 - b.y0) };
    let list = list_for(d, job.page)?;
    render_job_doc(&d.doc, list, size, job.kind)
}
EOF
grep -n 'pub struct Rect' -A6 ~/.cargo/registry/src/*/mupdf-0.8.0/src/rect.rs | head -8; grep -n 'egui\|eframe' ../Cargo.toml; ls ../src/bin; grep -n 'name\|\[\[bin' ../Cargo.toml
