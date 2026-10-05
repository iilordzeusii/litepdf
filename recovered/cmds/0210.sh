cd /tmp/scratch/app && cat > src/main.rs <<'EOF'
use eframe::egui::{self, Color32, ColorImage, TextureHandle, Vec2, Rect, pos2};
use mupdf::{Colorspace, Document, Matrix};
use std::collections::HashMap;

struct App {
    doc: Option<Document>,
    sizes: Vec<Vec2>,           // page size in PDF points
    tex: HashMap<(usize, u32), TextureHandle>,
    zoom: f32,
    scroll: f32,
    path: String,
}

impl App {
    fn open(&mut self, p: &str) {
        if let Ok(d) = Document::open(p) {
            let n = d.page_count().unwrap_or(0);
            self.sizes = (0..n).filter_map(|i| d.load_page(i).ok()).filter_map(|pg| pg.bounds().ok()).map(|b| Vec2::new(b.x1 - b.x0, b.y1 - b.y0)).collect();
            self.doc = Some(d);
            self.tex.clear();
            self.path = p.to_string();
        }
    }
    fn page_tex(&mut self, ctx: &egui::Context, i: usize, scale: f32) -> Option<TextureHandle> {
        let key = (i, (scale * 100.0) as u32);
        if let Some(t) = self.tex.get(&key) { return Some(t.clone()); }
        let doc = self.doc.as_ref()?;
        let pg = doc.load_page(i as i32).ok()?;
        let pm = pg.to_pixmap(&Matrix::new_scale(scale, scale), &Colorspace::device_rgb(), false, true).ok()?;
        let (w, h) = (pm.width() as usize, pm.height() as usize);
        let img = ColorImage::from_rgb([w, h], pm.samples());
        let t = ctx.load_texture(format!("p{i}-{}", key.1), img, egui::TextureOptions::LINEAR);
        if self.tex.len() > 12 { self.tex.clear(); }
        self.tex.insert(key, t.clone());
        Some(t)
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) {
        let ppp = ctx.pixels_per_point();
        egui::TopBottomPanel::top("bar").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.heading("LitePDF");
                ui.label(format!("{}  |  {:.0}%  |  {} pages  |  dpi scale {:.2}", self.path, self.zoom * 100.0, self.sizes.len(), ppp));
            });
        });
        egui::CentralPanel::default().frame(egui::Frame::none().fill(Color32::from_gray(60))).show(ctx, |ui| {
            // pinch / ctrl+wheel zoom
            let zd = ui.input(|i| i.zoom_delta());
            if zd != 1.0 { self.zoom = (self.zoom * zd).clamp(0.1, 8.0); }
            let area = ui.available_rect_before_wrap();
            let sd = ui.input(|i| i.smooth_scroll_delta.y);
            self.scroll -= sd;
            let gap = 12.0;
            let total: f32 = self.sizes.iter().map(|s| s.y * self.zoom + gap).sum();
            self.scroll = self.scroll.clamp(0.0, (total - area.height()).max(0.0));
            let painter = ui.painter_at(area);
            let mut y = area.top() + gap - self.scroll;
            for i in 0..self.sizes.len() {
                let sz = self.sizes[i] * self.zoom;
                let x = area.center().x - sz.x / 2.0;
                let r = Rect::from_min_size(pos2(x, y), sz);
                if r.bottom() >= area.top() && r.top() <= area.bottom() {
                    painter.rect_filled(r.translate(Vec2::splat(2.0)), 0.0, Color32::from_black_alpha(80));
                    // render at physical pixels: zoom * pixels_per_point
                    if let Some(t) = self.page_tex(ctx, i, self.zoom * ppp) {
                        painter.image(t.id(), r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
                    }
                }
                y += sz.y + gap;
            }
        });
    }
}

fn main() -> eframe::Result<()> {
    let path = std::env::args().nth(1).unwrap_or_default();
    let mut app = App { doc: None, sizes: vec![], tex: HashMap::new(), zoom: 1.0, scroll: 0.0, path: String::new() };
    if !path.is_empty() { app.open(&path); }
    let opts = eframe::NativeOptions { viewport: egui::ViewportBuilder::default().with_inner_size([1000.0, 760.0]).with_title("LitePDF"), ..Default::default() };
    eframe::run_native("LitePDF", opts, Box::new(|_| Ok(Box::new(app))))
}
EOF
source ~/.cargo/env; (timeout 110 cargo build --release 2>&1 | grep -E "^error|warning: unused|Finished" -A5 | head -20)
