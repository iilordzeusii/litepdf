cd /tmp/scratch/app/src && python3 - <<'EOF'
s=open('app.rs').read()
def rep(old,new):
    global s
    assert old in s, old[:70]
    s=s.replace(old,new,1)
rep("pub enum Msg { Status(String), Reload(String), Ai(Result<String, String>) }","pub enum Msg { Status(String), Note(String), Reload(String, String), Ai(Result<String, String>) }")
rep("Msg::Reload(p) => { match PdfDocument::open(&p) { Ok(d) => { self.set_doc(d); self.dirty = true; self.status = \"Done (unsaved - use Save as)\".into(); }","Msg::Note(s) => { self.status = s; }\n            Msg::Reload(p, note) => { match PdfDocument::open(&p) { Ok(d) => { let keep = self.scroll; self.set_doc(d); self.scroll = keep; self.dirty = true; self.status = note; }")
rep("Msg::Ai(r) => { self.ai_busy = false; match r { Ok(t) => self.ai_out = t, Err(e) => self.ai_out = format!(\"Error: {e}\") } }","Msg::Ai(r) => { self.ai_busy = false; match r { Ok(t) => self.chat.push((false, t)), Err(e) => self.chat.push((false, format!(\"Error: {e}\"))) } }")
# merge reload usage? search other Msg::Reload sends
a=s.index("    fn start_ocr(&mut self) {"); b=s.index("    fn dialogs(")
s=s[:a]+'''    fn start_ocr(&mut self, from: usize, to: usize) {
        let Some(snap) = self.snapshot() else { return };
        let out = self.tmp("ocr.pdf"); let tx = self.tx.clone(); self.busy = "OCR running...".into(); self.status = format!("OCR starting, pages {}-{}...", from + 1, to + 1);
        std::thread::spawn(move || {
            let r = (|| -> Result<(usize, usize), String> {
                let mut d = PdfDocument::open(&snap).map_err(|e| e.to_string())?;
                let t0 = std::time::Instant::now();
                let tx2 = tx.clone();
                let n = extras::ocr_document(&mut d, from, to, &mut |i, c, w| { let _ = tx2.send(Msg::Note(format!("OCR page {} of {} ({} words so far, {}s)", i + 1, c, w, t0.elapsed().as_secs()))); })?;
                if n.0 > 0 { ops::save(&d, &out, true).map_err(|e| e.to_string())?; }
                Ok(n) })();
            let _ = tx.send(match r {
                Ok((0, _)) => Msg::Status("OCR found no words on the selected pages (details in ocr.log next to settings.json in %APPDATA%\\\\LitePDF)".into()),
                Ok((w, g)) => Msg::Reload(out, format!("OCR done: {w} words on {g} page(s). Unsaved - use Save as.")),
                Err(e) => Msg::Status(format!("OCR failed: {e}")) });
        });
    }
'''+s[b:]
rep('Dlg::Merge => "Merge", Dlg::None => ""','Dlg::Merge => "Merge", Dlg::Ocr => "OCR (English)", Dlg::None => ""')
rep("                Dlg::None => {}\n            }\n            if ui.button(\"Cancel\")","""                Dlg::Ocr => {
                    let n = self.sizes.len();
                    ui.label("Pages to OCR (adds a searchable, selectable text layer; page look and size stay the same):");
                    ui.horizontal(|ui| { ui.label("From"); ui.add(egui::TextEdit::singleline(&mut self.f1).desired_width(50.0)); ui.label("to"); ui.add(egui::TextEdit::singleline(&mut self.f2).desired_width(50.0)); ui.label(format!("of {n}")); });
                    ui.horizontal(|ui| {
                        if ui.button("Current page").clicked() { self.f1 = (self.cur_page + 1).to_string(); self.f2 = self.f1.clone(); }
                        if ui.button("All pages").clicked() { self.f1 = "1".into(); self.f2 = n.to_string(); }
                    });
                    if ui.button("Run OCR").clicked() {
                        let a: usize = self.f1.trim().parse().unwrap_or(0); let b: usize = self.f2.trim().parse().unwrap_or(0);
                        if a >= 1 && b >= a && b <= n { self.start_ocr(a - 1, b - 1); close = true; } else { self.status = format!("Enter a range between 1 and {n}"); }
                    }
                }
                Dlg::None => {}
            }
            if ui.button("Cancel")""")
rep('if ui.button("OCR (English)").clicked() { self.start_ocr(); ui.close(); }','if ui.button("OCR (English)...").clicked() { self.f1 = (self.cur_page + 1).to_string(); self.f2 = self.f1.clone(); self.dlg = Dlg::Ocr; ui.close(); }')
open('app.rs','w').write(s)
EOF
grep -n "fn ai_panel" -A40 app.rs | grep -n "fn ask_ai" | head -2; grep -n "fn ai_panel\|fn ask_ai\|pub fn b64" app.rs
