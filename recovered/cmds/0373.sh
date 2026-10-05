cd /tmp/scratch/app/src && python3 - <<'EOF'
import re
s=open('app.rs').read()
def rep(old,new,cnt=1):
    global s
    assert old in s, old[:60]
    s=s.replace(old,new,cnt)

# --- state
rep("pub struct TextEditState { pub page: usize, pub at: Pos2, pub text: String, pub fresh: bool }",
"pub struct TextEditState { pub page: usize, pub at: Pos2, pub text: String, pub fresh: bool, pub idx: Option<usize>, pub font: usize, pub size: f32, pub color: [f32; 3], pub w: f32 }")
rep("    pub busy: String,\n}","    pub busy: String,\n    pub chat: Vec<(bool, String)>, pub chat_input: String,\n    pub zoom_t: std::time::Instant, pub styled: bool, pub font: usize, pub fsize: f32, pub ocr_log_hint: String,\n}")
rep("pending: None, pending_path: String::new(),","chat: vec![], chat_input: String::new(), zoom_t: std::time::Instant::now(), styled: false, font: 0, fsize: 12.0, ocr_log_hint: String::new(), pending: None, pending_path: String::new(),")
rep("color: [1.0, 0.85, 0.0],","color: [0.0, 0.0, 0.0],")
rep("pub enum Dlg { None, Split, Compress, Protect, Sign, Password, Merge }","pub enum Dlg { None, Split, Compress, Protect, Sign, Password, Merge, Ocr }")
# tool click no color override
rep("self.commit_text(); self.tool = t; if t == Tool::Highlight { self.color = [1.0, 0.85, 0.0]; } if t == Tool::Ink { self.color = [0.1, 0.2, 0.9]; }","self.commit_text(); self.tool = t;")

# --- page_tex: debounce friendly
a=s.index("    fn page_tex("); b=s.index("    fn thumb(")
s=s[:a]+'''    fn page_tex(&mut self, ctx: &egui::Context, i: usize, scale: f32, settled: bool) -> Option<TextureHandle> {
        let sz = *self.sizes.get(i)?;
        let scale = scale.min(8192.0 / sz.x.max(sz.y).max(1.0));
        let key = (i, ((scale * 20.0).round() as u32).max(1));
        if let Some(t) = self.tex.get(&key) { return Some(t.clone()); }
        if !settled { // while zooming: stretch whatever we already have for this page
            let mut best: Option<(&(usize, u32), &TextureHandle)> = None;
            for (k, t) in self.tex.iter() { if k.0 == i { if best.map_or(true, |(bk, _)| (k.1 as i64 - key.1 as i64).abs() < (bk.1 as i64 - key.1 as i64).abs()) { best = Some((k, t)); } } }
            if let Some((_, t)) = best { return Some(t.clone()); }
        }
        let doc = self.doc.as_ref()?;
        let pg = doc.load_page(i as i32).ok()?;
        let sc = key.1 as f32 / 20.0;
        let pm = pg.to_pixmap(&Matrix::new_scale(sc, sc), &Colorspace::device_rgb(), false, true).ok()?;
        let img = ColorImage::from_rgb([pm.width() as usize, pm.height() as usize], pm.samples());
        let t = ctx.load_texture(format!("p{i}-{}", key.1), img, egui::TextureOptions::LINEAR);
        self.tex.retain(|k, _| k.0 != i);
        if self.tex.len() > 10 { self.tex.clear(); }
        self.tex.insert(key, t.clone());
        Some(t)
    }
'''+s[b:]
rep("self.page_tex(ctx, i, self.zoom * ppp)","self.page_tex(ctx, i, self.zoom * ppp, settled)")

# --- zoom: timestamp + settled
rep("            if zd != 1.0 { let old = self.zoom;","            if zd != 1.0 { self.zoom_t = std::time::Instant::now(); let old = self.zoom;")
rep("            let resp = ui.interact(area,","            let settled = self.zoom_t.elapsed() > std::time::Duration::from_millis(140);\n            if !settled { ctx.request_repaint_after(std::time::Duration::from_millis(150)); }\n            let resp = ui.interact(area,")

# --- Ctrl+C / A only when no text widget focused
rep("let copy = ui.input(|i| i.events.iter()","let typing = ctx.wants_keyboard_input();\n            let copy = !typing && ui.input(|i| i.events.iter()")
rep("if ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::A)) { if let Some((pg, _)) = to_pdf(&rects, area.center()) {","if !typing && ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::A)) { let hp = ui.input(|i| i.pointer.hover_pos()).filter(|p| area.contains(*p)).unwrap_or(area.center()); if let Some((pg, _)) = to_pdf(&rects, hp) {")

# --- commit_text rewrite
a=s.index("    pub fn commit_text(&mut self) {"); b=s.index("    pub fn ui(&mut self")
s=s[:a]+'''    pub fn commit_text(&mut self) {
        if let Some(e) = self.edit.take() {
            let t = e.text.trim_end().to_string();
            let lines: Vec<&str> = t.lines().collect();
            let k = ops::font_factor(e.font);
            let w = (lines.iter().map(|l| l.chars().count()).max().unwrap_or(1) as f32 * k * e.size + 10.0).max(e.w);
            let h = lines.len().max(1) as f32 * e.size * 1.25 + 6.0;
            let r = mupdf::Rect::new(e.at.x, e.at.y, e.at.x + w, e.at.y + h);
            if let Some(d) = self.doc.as_mut() {
                let res = match e.idx { Some(i) => ops::freetext_update(d, e.page as i32, i, r, &t, e.font, e.size, e.color), None if t.is_empty() => Ok(()), None => ops::add_freetext_f(d, e.page as i32, r, &t, e.font, e.size, e.color) };
                match res { Ok(_) => self.status = "Text saved".into(), Err(er) => self.status = format!("Text failed: {er}") }
            }
            self.font = e.font; self.fsize = e.size;
            self.invalidate(e.page);
        }
    }

'''+s[b:]
# Text tool click: edit existing or new
rep("""if resp.clicked() && self.edit.is_none() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) { self.edit = Some(TextEditState { page: pg, at: pp, text: String::new(), fresh: true }); } } }""",
"""if resp.clicked() && self.edit.is_none() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) {
                        let ex = self.doc.as_ref().and_then(|d| ops::freetext_at(d, pg as i32, Point::new(pp.x, pp.y)));
                        self.edit = Some(match ex { Some(f) => TextEditState { page: pg, at: pos2(f.rect.x0, f.rect.y0), text: f.text, fresh: true, idx: Some(f.idx), font: f.font, size: f.size, color: f.color, w: f.rect.x1 - f.rect.x0 },
                            None => TextEditState { page: pg, at: pp, text: String::new(), fresh: true, idx: None, font: self.font, size: self.fsize, color: self.color, w: 60.0 } });
                    } } }""")
# overlay rewrite
a=s.index("            // on-page text box\n"); b=s.index("            let _ = (Align2::CENTER_CENTER,);")
s=s[:a]+'''            // on-page text box (Enter = done, Shift+Enter = new line)
            if let Some(e) = &mut self.edit {
                let r = rects[e.page];
                let mut commit = false; let mut moved = vec2(0.0, 0.0);
                let at = r.min + e.at.to_vec2() * z;
                egui::Area::new(egui::Id::new("ftext")).fixed_pos(at - vec2(0.0, 30.0)).order(egui::Order::Foreground).show(ctx, |ui| {
                    egui::Frame::popup(ui.style()).inner_margin(4.0).show(ui, |ui| { ui.horizontal(|ui| {
                        let h = ui.add(egui::Label::new("Move").sense(egui::Sense::drag())); if h.dragged() { moved = h.drag_delta() / z; }
                        egui::ComboBox::from_id_salt("ffont").width(110.0).selected_text(ops::FONTS[e.font.min(2)].1).show_ui(ui, |ui| { for (k, (_, n)) in ops::FONTS.iter().enumerate() { ui.selectable_value(&mut e.font, k, *n); } });
                        ui.add(egui::DragValue::new(&mut e.size).range(6.0..=96.0).suffix(" pt"));
                        let mut c = Color32::from_rgb((e.color[0] * 255.0) as u8, (e.color[1] * 255.0) as u8, (e.color[2] * 255.0) as u8);
                        if ui.color_edit_button_srgba(&mut c).changed() { e.color = [c.r() as f32 / 255.0, c.g() as f32 / 255.0, c.b() as f32 / 255.0]; }
                        if ui.button("Done").clicked() { commit = true; }
                    }); });
                });
                egui::Area::new(egui::Id::new("ftext2")).fixed_pos(at).order(egui::Order::Foreground).show(ctx, |ui| {
                    egui::Frame::NONE.stroke(Stroke::new(1.0, Color32::from_rgb(40, 110, 255))).fill(Color32::from_white_alpha(235)).show(ui, |ui| {
                        let fam = match e.font { 1 => egui::FontFamily::Proportional, 2 => egui::FontFamily::Monospace, _ => egui::FontFamily::Proportional };
                        let col = Color32::from_rgb((e.color[0] * 255.0) as u8, (e.color[1] * 255.0) as u8, (e.color[2] * 255.0) as u8);
                        let te = egui::TextEdit::multiline(&mut e.text).font(FontId::new(e.size * z, fam)).text_color(col).desired_width((e.w.max(120.0)) * z).desired_rows(1).frame(egui::Frame::NONE)
                            .return_key(Some(egui::KeyboardShortcut::new(egui::Modifiers::SHIFT, egui::Key::Enter)));
                        let rr = ui.add(te);
                        if e.fresh { rr.request_focus(); e.fresh = false; }
                        if rr.has_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter) && !i.modifiers.shift) { commit = true; }
                    });
                });
                e.at += moved;
                if commit { self.commit_text(); }
            }
'''+s[b:]
open('app.rs','w').write(s)
EOF
grep -n "fn start_ocr" -A14 app.rs | head -30
