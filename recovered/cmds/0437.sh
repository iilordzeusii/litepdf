cd /tmp/scratch/app/src; python3 - <<'E'
s=open('app.rs').read()
s=s.replace("pub cur_page: usize,","pub cur_page: usize, pub ocr_force: bool, pub goto: String, pub last_title: String,",1)
s=s.replace("cur_page: 0, busy: String::new(),","cur_page: 0, ocr_force: false, goto: String::new(), last_title: String::new(), busy: String::new(),",1)
# title + toolbar name
s=s.replace("        egui::TopBottomPanel::top(\"bar\")","""        {
            let name = if self.path.is_empty() { "Untitled".to_string() } else { std::path::Path::new(&self.path).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default() };
            let title = format!("{}{} - LitePDF", name, if self.dirty { " *" } else { "" });
            if title != self.last_title { ctx.send_viewport_cmd(egui::ViewportCommand::Title(title.clone())); self.last_title = title; }
        }
        egui::TopBottomPanel::top("bar")""",1)
s=s.replace("""                self.menus(ui);
                ui.add_space(6.0); ui.separator(); ui.add_space(6.0);""","""                self.menus(ui);
                if self.doc.is_some() {
                    let nm = if self.path.is_empty() { "Untitled".to_string() } else { std::path::Path::new(&self.path).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default() };
                    let short: String = if nm.chars().count() > 26 { format!("{}...", nm.chars().take(24).collect::<String>()) } else { nm.clone() };
                    ui.add_space(4.0); ui.label(egui::RichText::new(format!("{}{}", short, if self.dirty { " *" } else { "" })).strong().size(13.5)).on_hover_text(if self.path.is_empty() { nm } else { self.path.clone() });
                }
                ui.add_space(6.0); ui.separator(); ui.add_space(6.0);""",1)
s=s.replace("""                    if ui.button("Find").clicked() { self.show_find = !self.show_find; }
                });""","""                    if ui.button("Find").clicked() { self.show_find = !self.show_find; }
                    let np = self.sizes.len();
                    if np > 0 {
                        ui.label(format!("/ {np}"));
                        let r = ui.add(egui::TextEdit::singleline(&mut self.goto).desired_width(34.0).horizontal_align(egui::Align::Center));
                        if r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                            if let Ok(p) = self.goto.trim().parse::<usize>() { let p = p.clamp(1, np) - 1; self.want_scroll_to = Some(self.sizes[..p].iter().map(|s| s.y * self.zoom + 12.0).sum()); self.cur_page = p; }
                        }
                        if !r.has_focus() { self.goto = (self.cur_page + 1).to_string(); }
                        ui.label("Page");
                    }
                });""",1)
# OCR
a=s.index("    fn start_ocr"); b=s.index("    fn dialogs")
s=s[:a]+'''    fn start_ocr(&mut self, from: usize, to: usize, force: bool) {
        let Some(snap) = self.snapshot() else { return };
        let out = self.tmp("ocr.pdf"); let tx = self.tx.clone(); self.busy = "OCR running...".into(); self.status = format!("OCR starting, pages {}-{}...", from + 1, to + 1);
        std::thread::spawn(move || {
            let r = (|| -> Result<extras::OcrStats, String> {
                let mut d = PdfDocument::open(&snap).map_err(|e| e.to_string())?;
                let tx2 = tx.clone();
                let n = extras::ocr_document(&mut d, from, to, force, &mut |m| { let _ = tx2.send(Msg::Note(m)); })?;
                if n.words > 0 { ops::save(&d, &out, true).map_err(|e| e.to_string())?; }
                Ok(n) })();
            let _ = tx.send(match r {
                Ok(n) if n.words == 0 && n.skipped > 0 && n.done == 0 && n.empty == 0 => Msg::Status(format!("Nothing to do: all {} selected page(s) already have text. Tick \\"Re-OCR pages that already have text\\" to force.", n.skipped)),
                Ok(n) if n.words == 0 => Msg::Status("OCR found no words on the selected pages (details in ocr.log next to settings.json in %APPDATA%\\\\LitePDF)".into()),
                Ok(n) => Msg::Reload(out, format!("OCR done: {} words on {} page(s){}{}. Engine: {}. Unsaved - use Save as.", n.words, n.done, if n.skipped > 0 { format!(", {} already had text (skipped)", n.skipped) } else { String::new() }, if n.empty > 0 { format!(", {} had no readable text", n.empty) } else { String::new() }, n.engine)),
                Err(e) => Msg::Status(format!("OCR failed: {e}")) });
        });
    }
'''+s[b:]
s=s.replace("""                    if ui.button("Run OCR").clicked() {""","""                    ui.checkbox(&mut self.ocr_force, "Re-OCR pages that already have text");
                    if ui.button("Run OCR").clicked() {""",1)
s=s.replace("self.start_ocr(a - 1, b - 1);","self.start_ocr(a - 1, b - 1, self.ocr_force);")
s=s.replace('"OCR (English)..."','"OCR (English)..."')
open('app.rs','w').write(s)
c=open('../Cargo.toml').read()
c=c.replace('tokio =','ort = { version = "=2.0.0-rc.10", default-features = false, features = ["std","load-dynamic","directml","ndarray"] }\ntokio =',1)
open('../Cargo.toml','w').write(c)
E
grep -n "Msg::Note\|Note(" app.rs | head -5; cd ..; source /tmp/scratch/wenv.sh >/dev/null 2>&1; (cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E "^(error|warning: unused)|-->|Finished" | head -40)
