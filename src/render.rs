//! Background page renderer. One worker thread owns its own copy of every open document
//! (MuPDF documents are not Send), renders tiles and low-res page bases into RGBA buffers,
//! and the UI thread only uploads finished buffers as textures.
use mupdf::pdf::PdfDocument;
use mupdf::{Colorspace, Device, DisplayList, IRect, Matrix, Pixmap};
use std::collections::HashMap;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Instant;

pub const TILE: i32 = 1024;
pub const BASE_SIDE: f32 = 640.0;
pub const WORKERS: usize = 3;

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Kind { Base, Tile { key: u32, tx: u16, ty: u16 }, Text }
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Job { pub tab: u32, pub epoch: u32, pub page: usize, pub kind: Kind }

#[derive(Clone)]
pub enum Src { Path(String), Bytes(Arc<Vec<u8>>) }
#[derive(Clone)]
pub enum Cmd {
    Open { tab: u32, epoch: u32, rev: u32, src: Src, pw: Option<String>, want_sizes: bool },
    Close { tab: u32 },
    Want(Vec<Job>),
}
#[derive(Clone, Debug)]
pub enum RawLink { Page(usize, Option<f32>), Uri(String) }
pub enum Res {
    Sizes { tab: u32, epoch: u32, sizes: Vec<(f32, f32)> },
    Img { job: Job, rev: u32, w: usize, h: usize, rgba: Vec<u8>, ms: f32, list_ms: f32, hit: bool, wid: usize },
    Text { job: Job, rev: u32, chars: Vec<(char, [f32; 4], u32)>, links: Vec<([f32; 4], RawLink)>, ms: f32 },
    Failed { tab: u32, epoch: u32, msg: String },
    JobFailed { job: Job, why: &'static str },
}

struct Shared { want: Vec<Job>, inbox: Vec<Vec<Cmd>>, quit: bool }
pub struct Worker { shared: Arc<(Mutex<Shared>, Condvar)>, pub rx: Receiver<Res>, pub ctx: Arc<Mutex<Option<egui::Context>>> }

impl Worker {
    pub fn new() -> Worker {
        let (res_tx, res_rx) = channel::<Res>();
        let ctx: Arc<Mutex<Option<egui::Context>>> = Arc::new(Mutex::new(None));
        let shared = Arc::new((Mutex::new(Shared { want: vec![], inbox: vec![vec![]; WORKERS], quit: false }), Condvar::new()));
        for id in 0..WORKERS {
            let (sh, tx, c2) = (shared.clone(), res_tx.clone(), ctx.clone());
            let _ = std::thread::Builder::new().name(format!("render{id}")).stack_size(32 << 20).spawn(move || run(id, sh, tx, c2));
        }
        Worker { shared, rx: res_rx, ctx }
    }
    pub fn send(&self, c: Cmd) {
        let (m, cv) = &*self.shared;
        if let Ok(mut g) = m.lock() {
            match c { Cmd::Want(w) => { g.want = w; } other => { for i in 0..WORKERS { g.inbox[i].push(other.clone()); } } }
            cv.notify_all();
        }
    }
}
impl Drop for Worker { fn drop(&mut self) { let (m, cv) = &*self.shared; if let Ok(mut g) = m.lock() { g.quit = true; } cv.notify_all(); } }

/// A private on-disk copy of the document the worker reads lazily. The worker therefore holds no copy of the file in RAM.
struct TempFile(std::path::PathBuf);
impl Drop for TempFile { fn drop(&mut self) { let _ = std::fs::remove_file(&self.0); } }
// field order matters: `doc` must close its file handle before the guard deletes the file
struct Doc { doc: PdfDocument, epoch: u32, rev: u32, lists: Vec<(usize, DisplayList)>, _tmp: Option<TempFile> }

fn tmp_dir() -> std::path::PathBuf { let d = std::env::temp_dir().join("litepdf-cache"); let _ = std::fs::create_dir_all(&d); d }
/// Remove cache files left by a crashed run (older than a day, so a second running instance is not disturbed).
pub fn purge_stale_cache() {
    if let Ok(rd) = std::fs::read_dir(tmp_dir()) { for e in rd.flatten() {
        let old = e.metadata().and_then(|m| m.modified()).ok().and_then(|t| t.elapsed().ok()).map_or(false, |d| d.as_secs() > 86400);
        if old { let _ = std::fs::remove_file(e.path()); }
    } }
}

fn wake(ctx: &Arc<Mutex<Option<egui::Context>>>) { if let Ok(g) = ctx.lock() { if let Some(c) = g.as_ref() { c.request_repaint(); } } }

fn run(id: usize, shared: Arc<(Mutex<Shared>, Condvar)>, tx: Sender<Res>, ctx: Arc<Mutex<Option<egui::Context>>>) {
    let mut docs: HashMap<u32, Doc> = HashMap::new(); let mut idle_shrink = false;
    let (m, cv) = &*shared;
    loop {
        let mut cmds: Vec<Cmd> = vec![]; let mut job: Option<Job> = None;
        {
            let mut g = m.lock().unwrap();
            loop {
                if g.quit { return; }
                if !g.inbox[id].is_empty() { cmds = std::mem::take(&mut g.inbox[id]); break; }
                if g.want.is_empty() && g.inbox[id].is_empty() && idle_shrink { mupdf::context::shrink_store(0); idle_shrink = false; }
                if !g.want.is_empty() {
                    // prefer a page this worker already has a display list for (it skips re-interpreting the page)
                    let mut pick = 0usize;
                    for (i, j) in g.want.iter().take(8).enumerate() { if docs.get(&j.tab).map_or(false, |d| d.lists.iter().any(|(p, _)| *p == j.page)) { pick = i; break; } }
                    job = Some(g.want.remove(pick)); break;
                }
                g = cv.wait(g).unwrap();
            }
        }
        for c in cmds {
            match c {
                Cmd::Close { tab } => { docs.remove(&tab); }
                Cmd::Want(_) => {}
                Cmd::Open { tab, epoch, rev, src, pw, want_sizes } => {
                    let r = (|| -> Result<(PdfDocument, TempFile), String> {
                        let tp = tmp_dir().join(format!("w{}-{}-{}-{}.pdf", std::process::id(), id, tab, epoch.wrapping_mul(1000).wrapping_add(rev)));
                        match src { Src::Path(p) => { std::fs::copy(&p, &tp).map_err(|e| e.to_string())?; } Src::Bytes(b) => { std::fs::write(&tp, &**b).map_err(|e| e.to_string())?; } }
                        let guard = TempFile(tp.clone());
                        let mut d = PdfDocument::open(tp.to_string_lossy().as_ref()).map_err(|e| e.to_string())?;
                        if d.needs_password().unwrap_or(false) { if !d.authenticate(pw.as_deref().unwrap_or("")).unwrap_or(false) { return Err("password".into()); } }
                        Ok((d, guard))
                    })();
                    match r {
                        Ok((d, guard)) => {
                            if want_sizes && id == 0 { let n = d.page_count().unwrap_or(0); let sizes: Vec<(f32, f32)> = (0..n).map(|i| d.load_page(i).ok().and_then(|p| p.bounds().ok()).map(|b| (b.x1 - b.x0, b.y1 - b.y0)).unwrap_or((595.0, 842.0))).collect(); let _ = tx.send(Res::Sizes { tab, epoch, sizes }); }
                            docs.insert(tab, Doc { doc: d, epoch, rev, lists: vec![], _tmp: Some(guard) });
                        }
                        Err(mm) => { if id == 0 { let _ = tx.send(Res::Failed { tab, epoch, msg: mm }); } }
                    }
                    wake(&ctx);
                }
            }
        }
        let Some(job) = job else { continue };
        idle_shrink = true;
        let Some(d) = docs.get_mut(&job.tab) else { continue };
        if d.epoch != job.epoch { let _ = tx.send(Res::JobFailed { job, why: "worker has an older/newer document epoch" }); wake(&ctx); continue; }
        let t = Instant::now();
        let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        match job.kind {
            Kind::Text => {
                if let Some((chars, links)) = extract_text(d, job.page) { let _ = tx.send(Res::Text { job, rev: d.rev, chars, links, ms: t.elapsed().as_secs_f32() * 1000.0 }); wake(&ctx); } else { let _ = tx.send(Res::JobFailed { job, why: "text extraction failed" }); wake(&ctx); }
            }
            _ => {
                if let Some((w, h, rgba, list_ms, hit)) = render_job(d, &job) {
                    let _ = tx.send(Res::Img { job, rev: d.rev, w, h, rgba, ms: t.elapsed().as_secs_f32() * 1000.0, list_ms, hit, wid: id });
                    wake(&ctx);
                } else { let _ = tx.send(Res::JobFailed { job, why: "render returned nothing (page load or pixmap failure)" }); wake(&ctx); }
            }
        }
        }));
        if caught.is_err() { let _ = tx.send(Res::JobFailed { job, why: "render thread panicked (font or engine error)" }); wake(&ctx); }
    }
}

fn extract_text(d: &Doc, page: usize) -> Option<(Vec<(char, [f32; 4], u32)>, Vec<([f32; 4], RawLink)>)> {
    let pg = d.doc.load_page(page as i32).ok()?;
    let mut chars: Vec<(char, [f32; 4], u32)> = vec![];
    if let Ok(tp) = pg.to_text_page(mupdf::TextPageFlags::PRESERVE_WHITESPACE) {
        let mut line_no = 0u32;
        for b in tp.blocks() { for l in b.lines() {
            for ch in l.chars() { if let Some(c) = ch.char() {
                let q = ch.quad();
                let xs = [q.ul.x, q.ur.x, q.ll.x, q.lr.x]; let ys = [q.ul.y, q.ur.y, q.ll.y, q.lr.y];
                chars.push((c, [xs.iter().cloned().fold(f32::MAX, f32::min), ys.iter().cloned().fold(f32::MAX, f32::min), xs.iter().cloned().fold(f32::MIN, f32::max), ys.iter().cloned().fold(f32::MIN, f32::max)], line_no));
            } }
            if let Some(last) = chars.last().cloned() { chars.push(('\n', [last.1[2], last.1[1], last.1[2], last.1[3]], line_no)); }
            line_no += 1;
        } }
    }
    let mut links = vec![];
    if let Ok(it) = pg.links() {
        for l in it {
            let dest = l.dest.or_else(|| d.doc.resolve_link(&l.uri).ok().flatten());
            let r = [l.bounds.x0, l.bounds.y0, l.bounds.x1, l.bounds.y1];
            if let Some(dd) = dest {
                use mupdf::DestinationKind as K;
                let y = match dd.kind { K::FitH { top } | K::FitBH { top } => top, K::XYZ { top, .. } => top, K::FitR { top, .. } => Some(top), _ => None };
                links.push((r, RawLink::Page(dd.loc.page_number as usize, y)));
            } else if !l.uri.is_empty() { links.push((r, RawLink::Uri(l.uri.clone()))); }
        }
    }
    Some((chars, links))
}

/// Pixel size of a page at scale `s` (pixels per point).
pub fn page_px(sz: (f32, f32), s: f32) -> (i32, i32) { (((sz.0 * s).ceil() as i32).max(1), ((sz.1 * s).ceil() as i32).max(1)) }
pub fn key_scale(key: u32) -> f32 { key as f32 / 256.0 }
pub fn scale_key(s: f32) -> u32 { ((s * 256.0).round() as u32).max(1) }

fn list_for<'a>(d: &'a mut Doc, page: usize) -> Option<(&'a DisplayList, bool)> {
    let mut hit = true;
    if let Some(i) = d.lists.iter().position(|(p, _)| *p == page) { let e = d.lists.remove(i); d.lists.push(e); }
    else {
        hit = false;
        let pg = d.doc.load_page(page as i32).ok()?;
        let l = pg.to_display_list(true).ok()?;
        d.lists.push((page, l));
        if d.lists.len() > 6 { d.lists.remove(0); }
    }
    d.lists.last().map(|(_, l)| (l, hit))
}

/// Render one job to RGBA. Tiles are cut from the same display list so neighbours match to the pixel.
pub fn render_job_doc(list: &DisplayList, size: (f32, f32), kind: Kind) -> Option<(usize, usize, Vec<u8>)> {
    let (scale, rect) = match kind {
        Kind::Text => return None,
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
        // the scissor is in DEVICE space (after the ctm), not page units; page units wrongly culled most text and vector content when zoomed
        let area = mupdf::Rect { x0: rect.x0 as f32 - 1.0, y0: rect.y0 as f32 - 1.0, x1: rect.x1 as f32 + 1.0, y1: rect.y1 as f32 + 1.0 };
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

fn render_job(d: &mut Doc, job: &Job) -> Option<(usize, usize, Vec<u8>, f32, bool)> {
    let t = Instant::now();
    let size = { let pg = d.doc.load_page(job.page as i32).ok()?; let b = pg.bounds().ok()?; (b.x1 - b.x0, b.y1 - b.y0) };
    let (list, hit) = list_for(d, job.page)?;
    let list_ms = t.elapsed().as_secs_f32() * 1000.0;
    let (w, h, rgba) = render_job_doc(list, size, job.kind)?;
    Some((w, h, rgba, list_ms, hit))
}
