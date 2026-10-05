use eframe::egui;
use mupdf::{Colorspace, Document, Matrix};

fn main() -> eframe::Result {
    eframe::run_native("LitePDF", eframe::NativeOptions::default(), Box::new(|_| Ok(Box::new(App { tex: None }))))
}
struct App { tex: Option<egui::TextureHandle> }
impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) {
        if self.tex.is_none() {
            if let Some(p) = std::env::args().nth(1) {
                if let Ok(doc) = Document::open(&p) { if let Ok(page) = doc.load_page(0) {
                    if let Ok(pm) = page.to_pixmap(&Matrix::new_scale(1.5, 1.5), &Colorspace::device_rgb(), false, false) {
                        let img = egui::ColorImage::from_rgb([pm.width() as usize, pm.height() as usize], pm.samples());
                        self.tex = Some(ctx.load_texture("p", img, Default::default()));
                    } } }
            }
        }
        egui::CentralPanel::default().show(ctx, |ui| { if let Some(t) = &self.tex { ui.image(t); } });
    }
}
