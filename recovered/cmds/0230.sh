cd /tmp/scratch/shot; cat > src/main.rs <<'EOF'
#[path = "/tmp/scratch/app/src/app.rs"]
mod app;
use app::App;
use egui_software_backend::{BufferMutRef, ColorFieldOrder, EguiSoftwareRender};
use std::collections::HashMap;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let (pdf, out) = (&a[1], &a[2]);
    let ppp: f32 = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(1.0);
    let (w, h) = (1000usize, 700usize);
    let ctx = egui::Context::default();
    let mut app = App { doc: None, sizes: vec![], tex: HashMap::new(), zoom: 1.0, scroll: 0.0, path: String::new() };
    app.open(pdf);
    let mut r = EguiSoftwareRender::new(ColorFieldOrder::Rgba);
    let mut buf = vec![[0u8; 4]; (w as f32 * ppp) as usize * (h as f32 * ppp) as usize];
    let mut last = None;
    for _ in 0..3 {
        let mut raw = egui::RawInput::default();
        raw.screen_rect = Some(egui::Rect::from_min_size(egui::pos2(0.0, 0.0), egui::vec2(w as f32, h as f32)));
        raw.viewports.get_mut(&raw.viewport_id).unwrap().native_pixels_per_point = Some(ppp);
        let o = ctx.run(raw, |c| app.ui(c));
        let jobs = ctx.tessellate(o.shapes, o.pixels_per_point);
        last = Some((jobs, o.textures_delta));
    }
    let (jobs, td) = last.unwrap();
    let (pw, ph) = ((w as f32 * ppp) as usize, (h as f32 * ppp) as usize);
    let mut b = BufferMutRef::new(&mut buf, pw, ph);
    r.render(&mut b, &jobs, &td, ppp);
    let mut img = Vec::with_capacity(pw * ph * 3);
    for p in &buf { img.extend_from_slice(&p[..3]); }
    let mut f = std::fs::File::create(out).unwrap();
    use std::io::Write;
    write!(f, "P6\n{} {}\n255\n", pw, ph).unwrap();
    f.write_all(&img).unwrap();
}
EOF
sleep 60; tail -2 /tmp/scratch/h1.log | cut -c1-120
