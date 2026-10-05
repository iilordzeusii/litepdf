cd /tmp/scratch/app; cat > src/bin/rendcli.rs <<'EOF'
#[path = "../render.rs"] mod render;
use mupdf::pdf::PdfDocument;
use mupdf::{Colorspace, Matrix};
use render::*;
use std::time::{Duration, Instant};
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let path = &a[1];
    let doc = PdfDocument::open(path).unwrap();
    let n = doc.page_count().unwrap();
    println!("pages {n}");
    // 1. seam test: tiles vs one-shot render
    for &s in &[1.25f32, 3.0] {
        let pg = doc.load_page(0).unwrap(); let b = pg.bounds().unwrap(); let sz = (b.x1 - b.x0, b.y1 - b.y0);
        let t0 = Instant::now();
        let pm = pg.to_pixmap(&Matrix::new_scale(s, s), &Colorspace::device_rgb(), false, true).unwrap();
        let full_ms = t0.elapsed().as_secs_f32() * 1000.0;
        let (pw, ph) = page_px(sz, s);
        let (w, h) = (pm.width() as i32, pm.height() as i32);
        let list = pg.to_display_list(true).unwrap();
        let key = scale_key(s);
        let mut maxd = 0i32; let mut bad = 0usize; let mut tiles = 0; let t1 = Instant::now();
        let (nx, ny) = ((pw + TILE - 1) / TILE, (ph + TILE - 1) / TILE);
        for ty in 0..ny { for tx in 0..nx {
            let (tw, th, rgba) = render_job_doc(&list, sz, Kind::Tile { key, tx: tx as u16, ty: ty as u16 }).unwrap(); tiles += 1;
            for y in 0..th { for x in 0..tw {
                let gx = tx as usize * TILE as usize + x; let gy = ty as usize * TILE as usize + y;
                if gx as i32 >= w || gy as i32 >= h { continue; }
                let si = (gy * w as usize + gx) * 3; let di = (y * tw + x) * 4;
                for c in 0..3 { let d = (pm.samples()[si + c] as i32 - rgba[di + c] as i32).abs(); maxd = maxd.max(d); if d > 2 { bad += 1; } }
            } }
        } }
        println!("scale {s}: page {pw}x{ph} px, one-shot {full_ms:.0} ms, {tiles} tiles total {:.0} ms, max channel diff {maxd}, px>2 diff {bad}", t1.elapsed().as_secs_f32() * 1000.0);
    }
    // 2. worker pipeline: base for 20 pages then tiles
    let w = Worker::new();
    let t0 = Instant::now();
    w.tx.send(Cmd::Open { tab: 1, epoch: 1, rev: 0, src: Src::Path(path.clone()), pw: None, want_sizes: true }).unwrap();
    match w.rx.recv_timeout(Duration::from_secs(60)).unwrap() { Res::Sizes { sizes, .. } => println!("sizes for {} pages in {:.0} ms", sizes.len(), t0.elapsed().as_secs_f32() * 1000.0), _ => println!("unexpected") }
    let np = (n as usize).min(30);
    let jobs: Vec<Job> = (0..np).map(|i| Job { tab: 1, epoch: 1, page: i, kind: Kind::Base }).collect();
    let t1 = Instant::now();
    w.tx.send(Cmd::Want(jobs)).unwrap();
    let mut got = 0; let mut first = 0.0; let mut sum = 0.0; let mut mx: f32 = 0.0;
    while got < np { if let Ok(Res::Img { ms, .. }) = w.rx.recv_timeout(Duration::from_secs(60)) { if got == 0 { first = t1.elapsed().as_secs_f32() * 1000.0; } got += 1; sum += ms; mx = mx.max(ms); } else { break; } }
    println!("bases: {got}/{np} first result after {first:.0} ms, all after {:.0} ms, avg {:.0} ms max {:.0} ms", t1.elapsed().as_secs_f32() * 1000.0, sum / got.max(1) as f32, mx);
    // 3. cancellation: send a long list, replace it right away, count stale renders
    let key = scale_key(1.5);
    let long: Vec<Job> = (0..np).map(|i| Job { tab: 1, epoch: 1, page: i, kind: Kind::Tile { key, tx: 0, ty: 0 } }).collect();
    w.tx.send(Cmd::Want(long)).unwrap(); std::thread::sleep(Duration::from_millis(60));
    let short = vec![Job { tab: 1, epoch: 1, page: np - 1, kind: Kind::Tile { key, tx: 0, ty: 0 } }];
    let t2 = Instant::now(); w.tx.send(Cmd::Want(short)).unwrap();
    let mut seen = 0; let mut last_after = 0.0;
    while let Ok(Res::Img { job, .. }) = w.rx.recv_timeout(Duration::from_millis(1500)) { seen += 1; if job.page == np - 1 { last_after = t2.elapsed().as_secs_f32() * 1000.0; break; } }
    println!("replace-list: wanted page {} arrived {last_after:.0} ms after the replace; results received meanwhile: {seen} (of {np} originally queued)", np - 1);
}
EOF
source /tmp/scratch/wenv.sh; timeout 100 cargo build --release --target x86_64-pc-windows-gnu --bin rendcli 2>&1 | grep -E '^error' -A9 | head -40; ls -la target/x86_64-pc-windows-gnu/release/rendcli.exe
