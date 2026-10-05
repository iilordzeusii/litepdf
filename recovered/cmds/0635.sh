cd /tmp/scratch/app; sed -i 's/^    fn invalidate(&mut self, page: usize)/    pub fn invalidate(\&mut self, page: usize)/' src/app.rs; cat > src/bin/uitest.rs <<'EOF'
#[path = "../ops.rs"] mod ops;
#[path = "../extras.rs"] mod extras;
#[path = "../ocr.rs"] mod ocr;
#[path = "../render.rs"] mod render;
#[path = "../app.rs"] mod app;
use app::App;
use std::time::{Duration, Instant};
fn frame(ctx: &egui::Context, app: &mut App, events: Vec<egui::Event>) -> f32 {
    let mut inp = egui::RawInput::default();
    inp.screen_rect = Some(egui::Rect::from_min_size(egui::pos2(0.0, 0.0), egui::vec2(1100.0, 760.0)));
    inp.events = events;
    inp.time = Some(START.with(|s| s.elapsed().as_secs_f64()));
    let t = Instant::now();
    let _ = ctx.run(inp, |c| app.ui(c));
    t.elapsed().as_secs_f32() * 1000.0
}
thread_local! { static START: Instant = Instant::now(); }
fn pump(ctx: &egui::Context, app: &mut App, n: usize, ev: impl Fn(usize) -> Vec<egui::Event>) -> (f32, f32, usize) {
    let (mut mx, mut sum, mut blank) = (0f32, 0f32, 0usize);
    for k in 0..n {
        let ms = frame(ctx, app, ev(k)); mx = mx.max(ms); sum += ms;
        std::thread::sleep(Duration::from_millis(6));
        // blank = a page that intersects the view has neither base nor tiles
        let first = app.cur_page; let any_blank = (first..(first + 1)).any(|p| app.view.bases.get(&p).is_none() && app.view.tiles.get(&p).map_or(true, |m| m.is_empty()));
        if any_blank { blank += 1; }
    }
    (mx, sum / n as f32, blank)
}
fn wheel(dy: f32) -> Vec<egui::Event> { vec![egui::Event::MouseWheel { unit: egui::MouseWheelUnit::Point, delta: egui::vec2(0.0, dy), modifiers: egui::Modifiers::NONE, phase: egui::TouchPhase::Move }, egui::Event::PointerMoved(egui::pos2(600.0, 400.0))] }
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let ctx = egui::Context::default(); ctx.set_pixels_per_point(1.25);
    let mut app = App::new();
    let t0 = Instant::now();
    app.open(&a[1]);
    println!("open() call took {:.0} ms; pages {}", t0.elapsed().as_secs_f32() * 1000.0, app.sizes.len());
    // first frames until the first page has pixels
    let mut first_ms = 0.0; let mut k = 0;
    loop { let ms = frame(&ctx, &mut app, vec![]); if k == 0 { first_ms = ms; } k += 1; std::thread::sleep(Duration::from_millis(5)); if app.view.tiles.get(&0).map_or(false, |m| !m.is_empty()) || t0.elapsed() > Duration::from_secs(10) { break; } }
    println!("first frame {first_ms:.1} ms; sharp page 0 after {:.0} ms ({k} frames); sizes_exact: {} pages; tiles={} mem={}MB", t0.elapsed().as_secs_f32() * 1000.0, app.sizes.len(), app.view.tile_count(), app.view.bytes >> 20);
    let (mx, av, bl) = pump(&ctx, &mut app, 200, |_| wheel(-30.0));
    println!("scroll 200 frames at -30px/frame: frame max {mx:.1} ms avg {av:.2} ms, frames with blank top page {bl}, now at page {}", app.cur_page + 1);
    let (mx, av, bl) = pump(&ctx, &mut app, 120, |_| wheel(-160.0));
    println!("fast scroll 120 frames at -160px/frame: frame max {mx:.1} ms avg {av:.2} ms, blank {bl}, page {}", app.cur_page + 1);
    let (mx, _, _) = pump(&ctx, &mut app, 60, |_| vec![]);
    println!("settle: frame max {mx:.1} ms; tiles={} mem={}MB", app.view.tile_count(), app.view.bytes >> 20);
    let z0 = app.zoom;
    let (mx, av, _) = pump(&ctx, &mut app, 30, |k| vec![egui::Event::Zoom(if k < 15 { 1.06 } else { 1.0 })]);
    println!("pinch zoom {z0:.2}->{:.2}: frame max {mx:.1} ms avg {av:.2} ms", app.zoom);
    let (mx, _, _) = pump(&ctx, &mut app, 60, |_| vec![]);
    let cp = app.cur_page; let have = app.view.tiles.get(&cp).map_or(0, |m| m.len());
    println!("after zoom settle: frame max {mx:.1} ms; sharp tiles on current page {have}");
    // edit: ink on current page -> invalidate
    let cp = app.cur_page;
    if let Some(d) = app.doc.as_mut() { let _ = ops::add_ink(d, cp as i32, vec![vec![(50.0, 50.0), (200.0, 120.0), (300.0, 60.0)]], [1.0, 0.0, 0.0], 3.0); }
    app.invalidate(cp);
    let rev0 = app.view.rev; let t1 = Instant::now();
    let ms = frame(&ctx, &mut app, vec![]);
    let tl = app.view.tiles.get(&cp).map(|m| m.values().map(|t| t.rev).max().unwrap_or(0)).unwrap_or(0);
    println!("edit shown on the next frame: that frame took {ms:.1} ms; tile rev on page = {tl} (worker copy rev {rev0})");
    let _ = pump(&ctx, &mut app, 80, |_| vec![]);
    println!("after refresh: worker rev {}, awaiting={} ({:.0} ms since edit)", app.view.rev, app.view.required(cp) > app.view.rev, t1.elapsed().as_secs_f32() * 1000.0);
    // tabs
    for p in &a[2..] { app.open(p); let _ = pump(&ctx, &mut app, 30, |_| vec![]); }
    println!("tabs: {} active {} pages-now {} tiles {} mem {}MB", app.tabs.len(), app.active, app.sizes.len(), app.view.tile_count(), app.view.bytes >> 20);
    let t = Instant::now(); app.switch_to(0); let sw = frame(&ctx, &mut app, vec![]); 
    let mut k = 0; while app.view.tiles.get(&app.cur_page).map_or(true, |m| m.is_empty()) && k < 400 { frame(&ctx, &mut app, vec![]); std::thread::sleep(Duration::from_millis(2)); k += 1; }
    println!("switch to tab 0: frame {sw:.1} ms, sharp again after {:.0} ms; scroll kept at page {}, rev kept {}", t.elapsed().as_secs_f32() * 1000.0, app.cur_page + 1, app.view.rev);
    let n0 = app.tabs.len(); app.close_tab(1); println!("close tab 1: tabs {} -> {}, active {}", n0, app.tabs.len(), app.active);
    app.open(&a[2.min(a.len() - 1)]); println!("re-open already open file -> tabs stay {}", app.tabs.len());
    while app.tabs.len() > 1 { app.close_tab(0); } app.close_tab(0); println!("closed all: tabs {} doc_open {}", app.tabs.len(), app.doc.is_some());
    let _ = frame(&ctx, &mut app, vec![]);
    println!("perf.log written: {}", extras::settings_path().with_file_name("perf.log").exists());
}
EOF
source /tmp/scratch/wenv.sh; timeout 110 cargo build --release --target x86_64-pc-windows-gnu --bin uitest 2>&1 | grep -E '^error' -A12 | head -60; ls -la target/x86_64-pc-windows-gnu/release/uitest.exe
