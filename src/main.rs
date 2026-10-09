#![cfg_attr(windows, windows_subsystem = "windows")]
mod ops;
mod extras;
mod ocr;
mod crash;
mod render;
mod convert;
mod dm;
mod gesture;
mod app;
use app::App;
use eframe::egui;
use std::collections::HashMap;
impl eframe::App for Wrap { fn ui(&mut self, _u: &mut egui::Ui, _f: &mut eframe::Frame) {} fn update(&mut self, ctx: &egui::Context, f: &mut eframe::Frame) { self.0.ui(ctx); if self.0.gl_finish.load(std::sync::atomic::Ordering::Relaxed) { if let Some(gl) = f.gl() { use eframe::glow::HasContext; unsafe { gl.finish(); } } } } }
struct Wrap(App);
fn main() -> eframe::Result<()> {
    crash::install(); render::purge_stale_cache();
    let argv: Vec<String> = std::env::args().collect();
    if argv.get(1).map(|s| s == "--ocr").unwrap_or(false) { std::process::exit(extras::ocr_child_main(&argv[2..])); }
    if argv.get(1).map(|s| s == "--crashtest").unwrap_or(false) { unsafe { std::ptr::write_volatile(std::ptr::null_mut::<u32>(), 1); } }
    let path = std::env::args().skip(1).find(|s| !s.starts_with("--")).unwrap_or_default();
    let mut app = App::new(); app.native_title = std::env::args().any(|s| s == "--native-title");
    if !path.is_empty() { app.open(&path); }
    let vsync = !argv.iter().any(|s| s == "--vsync=off");
    let opts = eframe::NativeOptions { vsync, viewport: egui::ViewportBuilder::default().with_inner_size([1240.0, 780.0]).with_title("LitePDF").with_decorations(argv.iter().any(|s| s == "--native-title")).with_min_inner_size([640.0, 420.0]).with_icon(egui::IconData { rgba: include_bytes!("../icon48.rgba").to_vec(), width: 48, height: 48 }), ..Default::default() };
    eframe::run_native("LitePDF", opts, Box::new(move |cc| {
        let mut app = app;
        if let Some(gl) = cc.gl.as_ref() { use eframe::glow::HasContext; let (r, v) = unsafe { (gl.get_parameter_string(eframe::glow::RENDERER), gl.get_parameter_string(eframe::glow::VENDOR)) }; app.perf.header = format!("GL renderer: {r} | vendor: {v} | vsync: {}", if vsync { "on" } else { "off" }); }
        #[cfg(windows)] { app.gpu_pref_probe(); }
        if !argv.iter().any(|s| s == "--dm=off") { use raw_window_handle::{HasWindowHandle, RawWindowHandle}; if let Ok(h) = cc.window_handle() { if let RawWindowHandle::Win32(w) = h.as_raw() { let r = dm::init(w.hwnd.get(), &cc.egui_ctx); eprintln!("direct manipulation: {:?}", r); } } }
        Ok(Box::new(Wrap(app)))
    }))
}

