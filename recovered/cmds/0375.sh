cd /tmp/scratch/app/src && python3 - <<'EOF'
s=open('app.rs').read()
def rep(old,new):
    global s
    assert old in s, old[:70]
    s=s.replace(old,new,1)
rep("pub enum Tool { Select, Highlight, Underline, Strike, Ink, Text, Eraser, Redact }","pub enum Tool { Select, Highlight, Underline, Strike, Ink, Text, Eraser, Redact, Sign }")
rep("    pub chat: Vec<(bool, String)>, pub chat_input: String,","    pub chat: Vec<(bool, String)>, pub chat_input: String,\n    pub sign_box: Option<(usize, mupdf::Rect)>, pub sign_strokes: Vec<Vec<Pos2>>, pub sign_cur: Vec<Pos2>, pub sign_start: Option<(usize, Pos2)>, pub sign_drag: Option<Pos2>,")
rep("chat: vec![], chat_input: String::new(),","chat: vec![], chat_input: String::new(), sign_box: None, sign_strokes: vec![], sign_cur: vec![], sign_start: None, sign_drag: None,")
# cursor
rep("Tool::Ink | Tool::Redact => egui::CursorIcon::Crosshair,","Tool::Ink | Tool::Redact | Tool::Sign => egui::CursorIcon::Crosshair,")
# tool handling
rep("                Tool::Redact => {\n","""                Tool::Sign => {
                    if resp.drag_started() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) { self.sign_start = Some((pg, pp)); } } }
                    if resp.dragged() { if let (Some(pos), Some((pg, _))) = (pos, self.sign_start) { let r = rects[pg]; self.sign_drag = Some(pos2((pos.x - r.left()) / z, (pos.y - r.top()) / z)); } }
                    if resp.drag_stopped() { if let (Some((pg, a)), Some(b)) = (self.sign_start.take(), self.sign_drag.take()) {
                        let r = mupdf::Rect::new(a.x.min(b.x), a.y.min(b.y), a.x.max(b.x), a.y.max(b.y));
                        if (r.x1 - r.x0) > 20.0 && (r.y1 - r.y0) > 10.0 { self.sign_box = Some((pg, r)); self.sign_strokes.clear(); self.sign_cur.clear(); }
                    } }
                }
                Tool::Redact => {
""")
rep("                if let (Some((pg, a)), Some(b)) = (self.redact_start, self.redact_cur) {","                if let (Some((pg, a)), Some(b)) = (self.sign_start, self.sign_drag) { if pg == i { painter.rect_stroke(Rect::from_two_pos(r.min + a.to_vec2() * z, r.min + b.to_vec2() * z), 0.0, Stroke::new(1.5, Color32::from_rgb(40, 110, 255)), StrokeKind::Middle); } }\n                if let (Some((pg, a)), Some(b)) = (self.redact_start, self.redact_cur) {")
rep('(Tool::Redact, "Redact")]','(Tool::Redact, "Redact"), (Tool::Sign, "Sign")]')
# pad window: add before self.dialogs(ctx) call in ui
rep("        self.dialogs(ctx);\n","        self.dialogs(ctx);\n        self.sign_pad(ctx);\n")
# methods + ai chat + markdown
a=s.index("    fn ai_panel("); b=s.index("pub fn b64")
s=s[:a]+'''    fn sign_pad(&mut self, ctx: &egui::Context) {
        let Some((pg, r)) = self.sign_box else { return };
        let (bw, bh) = (r.x1 - r.x0, r.y1 - r.y0);
        let pw = 460.0; let ph = (pw * bh / bw).clamp(90.0, 300.0);
        let mut close = false; let mut apply = false;
        egui::Window::new("Draw your signature").collapsible(false).resizable(false).anchor(Align2::CENTER_CENTER, vec2(0.0, 0.0)).show(ctx, |ui| {
            ui.label("Draw inside the box. It will be placed in the area you marked on the page.");
            let (rect, resp) = ui.allocate_exact_size(vec2(pw, ph), egui::Sense::drag());
            let p = ui.painter_at(rect);
            p.rect_filled(rect, 4.0, Color32::WHITE); p.rect_stroke(rect, 4.0, Stroke::new(1.0, Color32::from_gray(120)), StrokeKind::Inside);
            if resp.drag_started() { self.sign_cur.clear(); }
            if resp.dragged() { if let Some(pp) = resp.interact_pointer_pos() { let q = pos2(((pp.x - rect.left()) / pw).clamp(0.0, 1.0), ((pp.y - rect.top()) / ph).clamp(0.0, 1.0)); self.sign_cur.push(q); } }
            if resp.drag_stopped() && self.sign_cur.len() > 1 { let c = std::mem::take(&mut self.sign_cur); self.sign_strokes.push(c); }
            let col = Color32::from_rgb((self.color[0] * 255.0) as u8, (self.color[1] * 255.0) as u8, (self.color[2] * 255.0) as u8);
            for st in self.sign_strokes.iter().chain(std::iter::once(&self.sign_cur)) { if st.len() > 1 { p.add(egui::Shape::line(st.iter().map(|q| rect.min + vec2(q.x * pw, q.y * ph)).collect(), Stroke::new(2.0, col))); } }
            ui.horizontal(|ui| {
                if ui.button("Clear").clicked() { self.sign_strokes.clear(); self.sign_cur.clear(); }
                if ui.add_enabled(!self.sign_strokes.is_empty(), egui::Button::new("Place signature")).clicked() { apply = true; }
                if ui.button("Cancel").clicked() { close = true; }
            });
        });
        if apply {
            let m = 3.0; let (x0, y0, w, h) = (r.x0 + m, r.y0 + m, (bw - 2.0 * m).max(1.0), (bh - 2.0 * m).max(1.0));
            // keep the drawing's aspect ratio inside the box
            let asp = pw / ph; let (fw, fh) = if w / h > asp { (h * asp, h) } else { (w, w / asp) };
            let (ox, oy) = (x0 + (w - fw) / 2.0, y0 + (h - fh) / 2.0);
            let strokes: Vec<Vec<(f32, f32)>> = self.sign_strokes.iter().map(|st| st.iter().map(|q| (ox + q.x * fw, oy + q.y * fh)).collect()).collect();
            let (col, wd) = (self.color, (fh / 60.0).clamp(0.8, 3.0));
            if let Some(d) = self.doc.as_mut() { match ops::add_ink(d, pg as i32, strokes, col, wd) { Ok(_) => self.status = "Signature placed (it is visible and saved with the file)".into(), Err(e) => self.status = format!("Signature failed: {e}") } }
            self.invalidate(pg); close = true;
        }
        if close { self.sign_box = None; self.sign_strokes.clear(); self.sign_cur.clear(); }
    }
    fn ai_panel(&mut self, ctx: &egui::Context) {
        egui::SidePanel::right("ai").default_width(360.0).show(ctx, |ui| {
            ui.horizontal(|ui| { ui.heading("AI chat"); ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| { if ui.button("New chat").clicked() { self.chat.clear(); } }); });
            egui::CollapsingHeader::new("Settings").default_open(self.settings.key.is_empty()).show(ui, |ui| {
                ui.horizontal(|ui| { ui.label("Provider"); egui::ComboBox::from_id_salt("prov").selected_text(self.settings.provider.clone()).show_ui(ui, |ui| { ui.selectable_value(&mut self.settings.provider, "Gemini".into(), "Gemini"); ui.selectable_value(&mut self.settings.provider, "OpenRouter".into(), "OpenRouter"); }); });
                ui.horizontal(|ui| { ui.label("API key"); ui.add(egui::TextEdit::singleline(&mut self.settings.key).password(true).desired_width(200.0)); });
                ui.horizontal(|ui| { ui.label("Model"); ui.add(egui::TextEdit::singleline(&mut self.settings.model).hint_text("type any model name").desired_width(200.0)); });
                ui.small("Key is stored in plain text in a settings file in your user profile on this PC. It is not put in PDFs or the repo.");
                ui.checkbox(&mut self.ai_use_text, "Send current page text"); ui.checkbox(&mut self.ai_scope_doc, "Send text of whole document"); ui.checkbox(&mut self.ai_use_image, "Send current page image");
            });
            ui.separator();
            let h = ui.available_height() - 90.0;
            egui::ScrollArea::vertical().max_height(h.max(80.0)).stick_to_bottom(true).auto_shrink([false, false]).show(ui, |ui| {
                for (u, t) in self.chat.iter() {
                    if *u { egui::Frame::NONE.fill(Color32::from_rgb(38, 70, 120)).corner_radius(8.0).inner_margin(8.0).show(ui, |ui| { ui.set_width(ui.available_width()); ui.add(egui::Label::new(egui::RichText::new(t).color(Color32::WHITE)).selectable(true)); }); }
                    else { egui::Frame::NONE.fill(Color32::from_gray(45)).corner_radius(8.0).inner_margin(8.0).show(ui, |ui| { ui.set_width(ui.available_width()); md(ui, t); }); }
                    ui.add_space(6.0);
                }
                if self.ai_busy { ui.horizontal(|ui| { ui.spinner(); ui.label("thinking..."); }); }
            });
            ui.separator();
            let r = ui.add(egui::TextEdit::multiline(&mut self.chat_input).desired_rows(2).desired_width(f32::INFINITY).hint_text("Ask about this PDF... (Enter sends, Shift+Enter new line)").return_key(Some(egui::KeyboardShortcut::new(egui::Modifiers::SHIFT, egui::Key::Enter))));
            let enter = r.has_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter) && !i.modifiers.shift);
            ui.horizontal(|ui| {
                if (ui.add_enabled(!self.ai_busy && self.doc.is_some(), egui::Button::new("Send")).clicked() || enter) && !self.ai_busy && !self.chat_input.trim().is_empty() { self.ask_ai(); r.request_focus(); }
                if ui.button("Copy last answer").clicked() { if let Some((_, t)) = self.chat.iter().rev().find(|(u, _)| !u) { ctx.copy_text(t.clone()); } }
            });
        });
    }
    fn ask_ai(&mut self) {
        extras::save_settings(&self.settings);
        let c = self.cur_page.min(self.sizes.len().saturating_sub(1));
        let mut text = None; let mut img = None;
        if self.ai_use_text || self.ai_scope_doc {
            let pages: Vec<usize> = if self.ai_scope_doc { (0..self.sizes.len()).collect() } else { vec![c] };
            let mut t = String::new();
            if let Some(d) = &self.doc { for i in pages { if let Ok(pg) = d.load_page(i as i32) { if let Ok(tp) = pg.to_text_page(TextPageFlags::empty()) { if let Ok(s) = tp.to_text() { t.push_str(&format!("--- page {} ---\\n{}\\n", i + 1, s)); } } } } }
            text = Some(t);
        }
        if self.ai_use_image { if let Some(d) = &self.doc { if let Ok(pg) = d.load_page(c as i32) {
            if let Ok(pm) = pg.to_pixmap(&Matrix::new_scale(1.6, 1.6), &Colorspace::device_rgb(), false, true) {
                let mut jpg = vec![]; let enc = jpeg_encoder::Encoder::new(&mut jpg, 80);
                if enc.encode(pm.samples(), pm.width() as u16, pm.height() as u16, jpeg_encoder::ColorType::Rgb).is_ok() { img = Some(b64(&jpg)); } } } } }
        let q = std::mem::take(&mut self.chat_input); self.chat.push((true, q.trim().to_string()));
        let (s, h, tx) = (self.settings.clone(), self.chat.clone(), self.tx.clone());
        self.ai_busy = true;
        std::thread::spawn(move || { let r = extras::ai_chat(&s, &h, text.as_deref(), img.as_deref()); let _ = tx.send(Msg::Ai(r)); });
    }
}

/// Small Markdown renderer for chat answers: headings, bullets, numbered lists, fenced code, **bold**, *italic*, `code`.
pub fn md(ui: &mut egui::Ui, text: &str) {
    let mut in_code = false; let mut code = String::new();
    for line in text.lines() {
        if line.trim_start().starts_with("```") {
            if in_code { egui::Frame::NONE.fill(Color32::from_gray(25)).corner_radius(4.0).inner_margin(6.0).show(ui, |ui| { ui.set_width(ui.available_width()); ui.add(egui::Label::new(egui::RichText::new(code.trim_end()).monospace().size(12.5)).selectable(true)); }); code.clear(); }
            in_code = !in_code; continue;
        }
        if in_code { code.push_str(line); code.push('\\n'); continue; }
        let t = line.trim_start(); let indent = (line.len() - t.len()) as f32 * 3.0;
        if t.is_empty() { ui.add_space(4.0); continue; }
        let (body, size, lead) = if let Some(h) = t.strip_prefix("### ") { (h, 15.0, None) } else if let Some(h) = t.strip_prefix("## ") { (h, 17.0, None) } else if let Some(h) = t.strip_prefix("# ") { (h, 19.0, None) }
            else if let Some(b) = t.strip_prefix("- ").or_else(|| t.strip_prefix("* ")) { (b, 14.0, Some("\\u{2022} ".to_string())) }
            else { let d = t.chars().take_while(|c| c.is_ascii_digit()).count(); if d > 0 && t[d..].starts_with(". ") { (&t[d + 2..], 14.0, Some(format!("{}. ", &t[..d]))) } else { (t, 14.0, None) } };
        let heading = size > 14.5;
        let mut job = egui::text::LayoutJob::default(); job.wrap.max_width = (ui.available_width() - indent).max(40.0);
        let norm = Color32::from_gray(225); let strong = Color32::WHITE;
        let fmt = |color: Color32, mono: bool, italic: bool| egui::TextFormat { font_id: if mono { FontId::monospace(size - 1.0) } else { FontId::proportional(size) }, color, italics: italic, background: if mono { Color32::from_gray(28) } else { Color32::TRANSPARENT }, ..Default::default() };
        if let Some(l) = lead { job.append(&l, 0.0, fmt(norm, false, false)); }
        let ch: Vec<char> = body.chars().collect(); let mut i = 0; let mut buf = String::new();
        let mut bold = heading; let mut ital = false;
        while i < ch.len() {
            if ch[i] == '*' && ch.get(i + 1) == Some(&'*') { job.append(&buf, 0.0, fmt(if bold { strong } else { norm }, false, ital)); buf.clear(); bold = !bold; i += 2; }
            else if ch[i] == '*' { job.append(&buf, 0.0, fmt(if bold { strong } else { norm }, false, ital)); buf.clear(); ital = !ital; i += 1; }
            else if ch[i] == '`' { job.append(&buf, 0.0, fmt(if bold { strong } else { norm }, false, ital)); buf.clear(); i += 1; let mut c = String::new(); while i < ch.len() && ch[i] != '`' { c.push(ch[i]); i += 1; } i += 1; job.append(&c, 0.0, fmt(Color32::from_rgb(255, 200, 120), true, false)); }
            else { buf.push(ch[i]); i += 1; }
        }
        job.append(&buf, 0.0, fmt(if bold { strong } else { norm }, false, ital));
        ui.horizontal_wrapped(|ui| { ui.add_space(indent); ui.add(egui::Label::new(job).selectable(true)); });
    }
}

'''+s[b:]
open('app.rs','w').write(s)
EOF
echo "18:45 app.rs: ocr dialog, freetext edit overlay, zoom debounce, ctrl+a fix, sign pad, ai chat+md patched; next toolbar style+zoom buttons, compile" >> ~/NOTES_native.md
