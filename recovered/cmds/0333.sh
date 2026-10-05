cd /tmp/scratch/app/src && cat >> app.rs <<'EOF'

fn pick_open(multi: bool) -> Vec<String> {
    #[cfg(windows)] { let d = rfd::FileDialog::new().add_filter("PDF", &["pdf"]); return if multi { d.pick_files().unwrap_or_default().into_iter().map(|p| p.to_string_lossy().into_owned()).collect() } else { d.pick_file().map(|p| vec![p.to_string_lossy().into_owned()]).unwrap_or_default() }; }
    #[allow(unreachable_code)] { let _ = multi; vec![] }
}
fn pick_save(name: &str) -> Option<String> {
    #[cfg(windows)] { return rfd::FileDialog::new().add_filter("PDF", &["pdf"]).set_file_name(name).save_file().map(|p| p.to_string_lossy().into_owned()); }
    #[allow(unreachable_code)] { let _ = name; None }
}
fn pick_p12() -> Option<String> {
    #[cfg(windows)] { return rfd::FileDialog::new().add_filter("Certificate", &["p12", "pfx"]).pick_file().map(|p| p.to_string_lossy().into_owned()); }
    #[allow(unreachable_code)] None
}

impl App {
    fn tmp(&self, n: &str) -> String { std::env::temp_dir().join(format!("litepdf-{}-{n}", std::process::id())).to_string_lossy().into_owned() }
    /// Write the current (possibly edited) document to a temp file for file-based operations.
    fn snapshot(&mut self) -> Option<String> {
        let t = self.tmp("snap.pdf");
        match self.doc.as_ref().map(|d| ops::save(d, &t, false)) { Some(Ok(_)) => Some(t), Some(Err(e)) => { self.status = format!("Snapshot failed: {e}"); None } None => None }
    }
    pub fn poll(&mut self) {
        while let Ok(m) = self.rx.try_recv() { match m {
            Msg::Status(s) => { self.status = s; self.busy.clear(); }
            Msg::Reload(p) => { match PdfDocument::open(&p) { Ok(d) => { self.set_doc(d); self.dirty = true; self.status = "Done (unsaved - use Save as)".into(); } Err(e) => self.status = format!("Reload failed: {e}") } self.busy.clear(); }
            Msg::Ai(r) => { self.ai_busy = false; match r { Ok(t) => self.ai_out = t, Err(e) => self.ai_out = format!("Error: {e}") } }
        } }
    }
    fn reload_edit(&mut self) { if let Some(d) = &self.doc { if let Ok(n) = ops::reload(d) { self.set_doc(n); self.dirty = true; } } }
    fn page_op(&mut self, f: impl FnOnce(&mut PdfDocument) -> Result<(), mupdf::Error>) {
        if let Some(d) = self.doc.as_mut() { if let Err(e) = f(d) { self.status = format!("Failed: {e}"); return; } }
        self.reload_edit();
    }
    fn menus(&mut self, ui: &mut egui::Ui) {
        ui.menu_button("File", |ui| {
            if ui.button("Open...  Ctrl+O").clicked() { if let Some(p) = pick_open(false).first() { self.open(p); } ui.close(); }
            if ui.button("Save  Ctrl+S").clicked() { if self.path.is_empty() { if let Some(p) = pick_save("document.pdf") { self.save_to(&p); } } else { let p = self.path.clone(); self.save_to(&p); } ui.close(); }
            if ui.button("Save as...").clicked() { if let Some(p) = pick_save("document.pdf") { self.save_to(&p); } ui.close(); }
            ui.separator();
            if ui.button("Merge with other PDFs...").clicked() { self.dlg = Dlg::Merge; ui.close(); }
            if ui.button("Split...").clicked() { self.f1 = "1-1".into(); self.dlg = Dlg::Split; ui.close(); }
            if ui.button("Compress...").clicked() { self.dlg = Dlg::Compress; ui.close(); }
            if ui.button("Password and permissions...").clicked() { self.f1.clear(); self.f2.clear(); self.dlg = Dlg::Protect; ui.close(); }
        });
        ui.menu_button("Pages", |ui| {
            let n = self.sizes.len(); let c = self.cur_page.min(n.saturating_sub(1));
            ui.label(format!("Current page: {}", c + 1));
            if ui.button("Rotate right").clicked() { self.page_op(|d| ops::rotate_page(d, c, 90)); ui.close(); }
            if ui.button("Rotate left").clicked() { self.page_op(|d| ops::rotate_page(d, c, -90)); ui.close(); }
            if ui.button("Move up").clicked() && c > 0 { self.page_op(|d| ops::move_page(d, c, c - 1)); ui.close(); }
            if ui.button("Move down").clicked() && c + 1 < n { self.page_op(|d| ops::move_page(d, c, c + 1)); ui.close(); }
            if ui.button("Delete page").clicked() && n > 1 { self.page_op(|d| ops::delete_page(d, c)); ui.close(); }
        });
        ui.menu_button("Tools", |ui| {
            if ui.button("OCR (English)").clicked() { self.start_ocr(); ui.close(); }
            if ui.button("Sign with certificate...").clicked() { self.f1.clear(); self.f2.clear(); self.f3 = "Approved".into(); self.dlg = Dlg::Sign; ui.close(); }
        });
        if ui.selectable_label(self.show_ai, "AI").clicked() { self.show_ai = !self.show_ai; }
    }
    fn start_ocr(&mut self) {
        let Some(snap) = self.snapshot() else { return };
        let out = self.tmp("ocr.pdf"); let tx = self.tx.clone(); self.busy = "OCR running...".into(); self.status = "OCR running...".into();
        std::thread::spawn(move || {
            let r = (|| -> Result<usize, String> {
                let mut d = PdfDocument::open(&snap).map_err(|e| e.to_string())?;
                let n = extras::ocr_document(&mut d, &mut |_, _| {})?;
                ops::save(&d, &out, true).map_err(|e| e.to_string())?; Ok(n) })();
            let _ = tx.send(match r { Ok(n) => { let _ = tx.send(Msg::Status(format!("OCR found {n} words"))); Msg::Reload(out) } Err(e) => Msg::Status(format!("OCR failed: {e}")) });
        });
    }
    fn dialogs(&mut self, ctx: &egui::Context) {
        if self.dlg == Dlg::None { return; }
        let mut close = false;
        let title = match self.dlg { Dlg::Split => "Split", Dlg::Compress => "Compress", Dlg::Protect => "Password and permissions", Dlg::Sign => "Sign with certificate", Dlg::Password => "Password required", Dlg::Merge => "Merge", Dlg::None => "" };
        egui::Window::new(title).collapsible(false).resizable(false).anchor(Align2::CENTER_CENTER, vec2(0.0, 0.0)).show(ctx, |ui| {
            match self.dlg {
                Dlg::Password => {
                    ui.label("This PDF is protected. Enter the password:");
                    let r = ui.add(egui::TextEdit::singleline(&mut self.f1).password(true));
                    if ui.button("Open").clicked() || (r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter))) {
                        if let Some(mut d) = self.pending.take() { if d.authenticate(&self.f1).unwrap_or(false) { self.set_doc(d); self.path = self.pending_path.clone(); self.dirty = false; self.status = "Opened".into(); close = true; } else { self.status = "Wrong password".into(); self.pending = Some(d); } }
                    }
                }
                Dlg::Merge => {
                    ui.label("The open document is first, then the files you choose, in order.");
                    if ui.button("Choose PDFs and merge...").clicked() {
                        let files = pick_open(true);
                        if !files.is_empty() { if let Some(snap) = self.snapshot() {
                            let out = self.tmp("merged.pdf"); let mut all = vec![snap]; all.extend(files);
                            let refs: Vec<&str> = all.iter().map(|s| s.as_str()).collect();
                            match ops::merge(&refs, &out) { Ok(_) => { if let Ok(d) = PdfDocument::open(&out) { self.set_doc(d); self.dirty = true; self.status = "Merged (unsaved - use Save as)".into(); } } Err(e) => self.status = format!("Merge failed: {e}") }
                        } } close = true;
                    }
                }
                Dlg::Split => {
                    ui.label("Page ranges, e.g. 1-3,4-6,7-7. Each range becomes its own file.");
                    ui.text_edit_singleline(&mut self.f1);
                    if ui.button("Split...").clicked() {
                        let n = self.sizes.len();
                        let ranges: Vec<(usize, usize)> = self.f1.split(',').filter_map(|r| { let mut it = r.trim().split('-'); let a: usize = it.next()?.trim().parse().ok()?; let b: usize = it.next().map(|x| x.trim().parse().ok()).unwrap_or(Some(a))?; if a >= 1 && b >= a && b <= n { Some((a - 1, b - 1)) } else { None } }).collect();
                        if ranges.is_empty() { self.status = "Invalid ranges".into(); } else if let Some(out) = pick_save("part.pdf") { if let Some(snap) = self.snapshot() {
                            let pre = out.trim_end_matches(".pdf").to_string();
                            match ops::split_ranges(&snap, &ranges, &pre) { Ok(v) => self.status = format!("Wrote {} files ({}_N.pdf)", v.len(), pre), Err(e) => self.status = format!("Split failed: {e}") } } }
                        close = true;
                    }
                }
                Dlg::Compress => {
                    ui.label("JPEG quality for images (lower = smaller):"); ui.add(egui::Slider::new(&mut self.quality, 20.0..=95.0));
                    if ui.button("Compress and save as...").clicked() {
                        if let Some(out) = pick_save("compressed.pdf") { if let Some(snap) = self.snapshot() {
                            match ops::compress(&snap, &out, 1600, self.quality as u8) { Ok((a, b)) => { let (s0, s1) = (std::fs::metadata(&snap).map(|m| m.len()).unwrap_or(0), std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0)); self.status = format!("Compressed {a}/{b} images: {} KB to {} KB", s0 / 1024, s1 / 1024); } Err(e) => self.status = format!("Compress failed: {e}") } } }
                        close = true;
                    }
                }
                Dlg::Protect => {
                    ui.horizontal(|ui| { ui.label("Open password:"); ui.add(egui::TextEdit::singleline(&mut self.f1).password(true)); });
                    ui.horizontal(|ui| { ui.label("Owner password:"); ui.add(egui::TextEdit::singleline(&mut self.f2).password(true)); });
                    ui.checkbox(&mut self.perm_print, "Allow printing"); ui.checkbox(&mut self.perm_copy, "Allow copying text"); ui.checkbox(&mut self.perm_edit, "Allow editing");
                    if ui.button("Encrypt and save as...").clicked() {
                        if let Some(out) = pick_save("protected.pdf") { if let Some(snap) = self.snapshot() {
                            use mupdf::pdf::Permission as P;
                            let mut p = P::ACCESSIBILITY; if self.perm_print { p |= P::PRINT | P::PRINT_HQ; } if self.perm_copy { p |= P::COPY; } if self.perm_edit { p |= P::MODIFY | P::ANNOTATE | P::FORM | P::ASSEMBLE; }
                            let owner = if self.f2.is_empty() { self.f1.clone() } else { self.f2.clone() };
                            match ops::encrypt(&snap, &out, &self.f1, &owner, p) { Ok(_) => self.status = "Encrypted (AES-256)".into(), Err(e) => self.status = format!("Encrypt failed: {e}") } } }
                        close = true;
                    }
                }
                Dlg::Sign => {
                    ui.horizontal(|ui| { ui.label("Certificate (.p12/.pfx):"); ui.text_edit_singleline(&mut self.f1); if ui.button("Browse").clicked() { if let Some(p) = pick_p12() { self.f1 = p; } } });
                    ui.horizontal(|ui| { ui.label("Certificate password:"); ui.add(egui::TextEdit::singleline(&mut self.f2).password(true)); });
                    ui.horizontal(|ui| { ui.label("Reason:"); ui.text_edit_singleline(&mut self.f3); });
                    if ui.button("Sign and save as...").clicked() {
                        if let Some(out) = pick_save("signed.pdf") { if let Some(snap) = self.snapshot() {
                            match extras::sign_pdf(&snap, &self.f1, &self.f2, &out, &self.f3) { Ok(_) => self.status = format!("Signed: {out}"), Err(e) => self.status = e } } }
                        self.f2.clear(); close = true;
                    }
                }
                Dlg::None => {}
            }
            if ui.button("Cancel").clicked() { close = true; }
        });
        if close { self.dlg = Dlg::None; }
    }
    fn ai_panel(&mut self, ctx: &egui::Context) {
        egui::SidePanel::right("ai").default_width(320.0).show(ctx, |ui| {
            ui.heading("AI");
            ui.horizontal(|ui| { ui.label("Provider"); egui::ComboBox::from_id_salt("prov").selected_text(self.settings.provider.clone()).show_ui(ui, |ui| { ui.selectable_value(&mut self.settings.provider, "Gemini".into(), "Gemini"); ui.selectable_value(&mut self.settings.provider, "OpenRouter".into(), "OpenRouter"); }); });
            ui.horizontal(|ui| { ui.label("API key"); ui.add(egui::TextEdit::singleline(&mut self.settings.key).password(true).desired_width(200.0)); });
            ui.horizontal(|ui| { ui.label("Model"); ui.add(egui::TextEdit::singleline(&mut self.settings.model).hint_text("type any model name").desired_width(200.0)); });
            ui.small("Key is saved only on this PC (in your user settings), never in the PDF or the repo.");
            ui.separator();
            ui.checkbox(&mut self.ai_use_text, "Send page text"); ui.checkbox(&mut self.ai_use_image, "Send page image"); ui.checkbox(&mut self.ai_scope_doc, "Text of whole document");
            ui.add(egui::TextEdit::multiline(&mut self.ai_prompt).desired_rows(3).desired_width(f32::INFINITY).hint_text("Ask about this PDF..."));
            ui.horizontal(|ui| {
                if ui.add_enabled(!self.ai_busy && self.doc.is_some(), egui::Button::new("Ask")).clicked() { self.ask_ai(); }
                if self.ai_busy { ui.spinner(); }
                if ui.button("Copy answer").clicked() { ctx.copy_text(self.ai_out.clone()); }
            });
            egui::ScrollArea::vertical().show(ui, |ui| { ui.add(egui::Label::new(&self.ai_out).selectable(true)); });
        });
    }
    fn ask_ai(&mut self) {
        extras::save_settings(&self.settings);
        let c = self.cur_page.min(self.sizes.len().saturating_sub(1));
        let mut text = None; let mut img = None;
        if self.ai_use_text || self.ai_scope_doc {
            let pages: Vec<usize> = if self.ai_scope_doc { (0..self.sizes.len()).collect() } else { vec![c] };
            let mut t = String::new();
            if let Some(d) = &self.doc { for i in pages { if let Ok(pg) = d.load_page(i as i32) { if let Ok(tp) = pg.to_text_page(TextPageFlags::empty()) { if let Ok(s) = tp.to_text() { t.push_str(&format!("--- page {} ---\n{}\n", i + 1, s)); } } } } }
            text = Some(t);
        }
        if self.ai_use_image { if let Some(d) = &self.doc { if let Ok(pg) = d.load_page(c as i32) {
            if let Ok(pm) = pg.to_pixmap(&Matrix::new_scale(1.6, 1.6), &Colorspace::device_rgb(), false, true) {
                let mut jpg = vec![]; let enc = jpeg_encoder::Encoder::new(&mut jpg, 80);
                if enc.encode(pm.samples(), pm.width() as u16, pm.height() as u16, jpeg_encoder::ColorType::Rgb).is_ok() { img = Some(b64(&jpg)); } } } } }
        let (s, p, tx) = (self.settings.clone(), self.ai_prompt.clone(), self.tx.clone());
        self.ai_busy = true; self.ai_out.clear();
        std::thread::spawn(move || { let r = extras::ai_ask(&s, &p, text.as_deref(), img.as_deref()); let _ = tx.send(Msg::Ai(r)); });
    }
}

pub fn b64(d: &[u8]) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut o = String::with_capacity(d.len() * 4 / 3 + 4);
    for c in d.chunks(3) { let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        o.push(T[(n >> 18) as usize & 63] as char); o.push(T[(n >> 12) as usize & 63] as char);
        o.push(if c.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' }); o.push(if c.len() > 2 { T[n as usize & 63] as char } else { '=' }); }
    o
}
EOF
python3 - <<'EOF'
s=open('app.rs').read()
# toolbar: replace Open/Save buttons block with menus
a=s.index("                #[cfg(windows)]\n                {\n                    if ui.button(\"Open\")")
b=s.index("                for (t, n) in [(Tool::Select")
s=s[:a]+"                self.menus(ui);\n                ui.separator();\n"+s[b:]
# ui entry: poll, dialogs, ai
s=s.replace("        let ppp = ctx.pixels_per_point();\n        // shortcuts","        let ppp = ctx.pixels_per_point();\n        self.poll();\n        if !self.busy.is_empty() { ctx.request_repaint_after(std::time::Duration::from_millis(200)); }\n        if self.ai_busy { ctx.request_repaint_after(std::time::Duration::from_millis(200)); }\n        // shortcuts")
s=s.replace("        egui::CentralPanel::default().frame(","        self.dialogs(ctx);\n        if self.show_ai { self.ai_panel(ctx); }\n        egui::CentralPanel::default().frame(")
# current page
s=s.replace("            let z = self.zoom;\n            let to_pdf","            let z = self.zoom;\n            if let Some(i) = rects.iter().position(|r| r.bottom() > area.center().y) { self.cur_page = i; }\n            let to_pdf")
open('app.rs','w').write(s)
m=open('main.rs').read()
if 'mod extras' not in m: m=m.replace("mod ops;","mod ops;\nmod extras;")
open('main.rs','w').write(m)
EOF
sed -i 's|^#\[path = "/tmp/scratch/app/src/app.rs"\]|#[path = "/tmp/scratch/app/src/extras.rs"]\nmod extras;\n#[path = "/tmp/scratch/app/src/app.rs"]|' /tmp/scratch/shot/src/main.rs
cd /tmp/scratch/shot && python3 - <<'EOF'
s=open('Cargo.toml').read()
if 'serde_json' not in s: s=s.replace('[dependencies]\n','[dependencies]\nserde_json = "1"\nunderskrift = { version = "0.1.4", default-features = false, features = ["blocking"] }\nlopdf = "0.39"\ntokio = { version = "1", features = ["rt"] }\njpeg-encoder = "0.6"\n',1)
open('Cargo.toml','w').write(s)
EOF
grep -n jpeg Cargo.toml; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 110 cargo build --release --bin shot 2>&1 | grep -E "^error" -A9 | head -60 | cut -c1-170
