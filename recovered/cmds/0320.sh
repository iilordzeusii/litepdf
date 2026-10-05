cd /tmp/scratch/app/src && cat >> ops.rs <<'EOF'

pub fn mark_redact(doc: &mut PdfDocument, page: i32, rect: Rect) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(page)?;
    let mut a = p.add_redact_annotation(rect)?;
    a.update()?; p.update()?;
    Ok(())
}

/// Apply every marked redaction in the document (true removal of the content under the boxes).
pub fn apply_all_redactions(doc: &mut PdfDocument) -> Result<usize, Error> {
    let mut n = 0;
    for i in 0..doc.page_count()? {
        let mut p = doc.load_pdf_page(i)?;
        let c = p.annotations().filter(|a| matches!(a.r#type(), Ok(PdfAnnotationType::Redact))).count();
        if c > 0 { p.apply_redactions()?; p.update()?; n += c; }
    }
    Ok(n)
}

pub fn delete_page(doc: &mut PdfDocument, i: usize) -> Result<(), Error> {
    let n = doc.page_count()? as usize;
    let order: Vec<usize> = (0..n).filter(|k| *k != i).collect();
    keep_pages(doc, &order)
}
pub fn move_page(doc: &mut PdfDocument, i: usize, to: usize) -> Result<(), Error> {
    let n = doc.page_count()? as usize;
    let mut order: Vec<usize> = (0..n).collect();
    let v = order.remove(i); order.insert(to.min(n - 1), v);
    keep_pages(doc, &order)
}
pub fn rotate_page(doc: &mut PdfDocument, i: usize, delta: i32) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(i as i32)?;
    let r = p.rotation()?;
    p.set_rotation((r + delta).rem_euclid(360))
}

/// Reload a document from its own bytes (needed after page-tree edits so the viewer sees them).
pub fn reload(doc: &PdfDocument) -> Result<PdfDocument, Error> {
    let mut buf: Vec<u8> = vec![];
    doc.write_to(&mut buf)?;
    PdfDocument::from_bytes(&buf)
}
EOF
cat > app.rs <<'EOF'
use crate::ops;
use egui::{self, Align2, Color32, ColorImage, FontId, Pos2, Rect, Stroke, StrokeKind, TextureHandle, Vec2, pos2, vec2};
use mupdf::pdf::PdfDocument;
use mupdf::{Colorspace, Matrix, Point, Quad, TextPageFlags};
use std::collections::HashMap;

#[derive(Clone)]
pub struct Ch { pub c: char, pub r: Rect, pub line: u32 }
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Sel { pub page: usize, pub a: usize, pub b: usize }
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Tool { Select, Highlight, Underline, Strike, Ink, Text, Eraser, Redact }

pub struct TextEditState { pub page: usize, pub at: Pos2, pub text: String, pub fresh: bool }

pub struct App {
    pub doc: Option<PdfDocument>,
    pub sizes: Vec<Vec2>,
    pub tex: HashMap<(usize, u32), TextureHandle>,
    pub thumbs: HashMap<usize, TextureHandle>,
    pub text: HashMap<usize, Vec<Ch>>,
    pub zoom: f32,
    pub scroll: f32,
    pub path: String,
    pub dirty: bool,
    pub sel: Option<Sel>,
    anchor: Option<(usize, usize)>,
    pub copied: String,
    pub tool: Tool,
    pub color: [f32; 3],
    pub ink_width: f32,
    pub ink_cur: Vec<Pos2>,
    pub ink_page: usize,
    pub redact_start: Option<(usize, Pos2)>,
    pub redact_cur: Option<Pos2>,
    pub edit: Option<TextEditState>,
    pub show_find: bool,
    pub find_q: String,
    pub find_hits: Vec<(usize, Rect)>,
    pub find_cur: usize,
    pub find_for: String,
    pub status: String,
    pub show_thumbs: bool,
    pub want_scroll_to: Option<f32>,
}

fn qrect(q: &Quad) -> Rect { let r = ops::quad_rect(q); Rect::from_min_max(pos2(r.x0, r.y0), pos2(r.x1, r.y1)) }

impl App {
    pub fn new() -> Self {
        App { doc: None, sizes: vec![], tex: HashMap::new(), thumbs: HashMap::new(), text: HashMap::new(), zoom: 1.0, scroll: 0.0, path: String::new(), dirty: false, sel: None, anchor: None, copied: String::new(),
            tool: Tool::Select, color: [1.0, 0.85, 0.0], ink_width: 2.0, ink_cur: vec![], ink_page: 0, redact_start: None, redact_cur: None, edit: None,
            show_find: false, find_q: String::new(), find_hits: vec![], find_cur: 0, find_for: String::new(), status: String::new(), show_thumbs: true, want_scroll_to: None }
    }
    pub fn open(&mut self, p: &str) {
        match PdfDocument::open(p) {
            Ok(d) => { self.set_doc(d); self.path = p.to_string(); self.dirty = false; self.status = format!("Opened {p}"); }
            Err(e) => self.status = format!("Open failed: {e}"),
        }
    }
    pub fn set_doc(&mut self, d: PdfDocument) {
        let n = d.page_count().unwrap_or(0);
        self.sizes = (0..n).filter_map(|i| d.load_page(i).ok()).filter_map(|pg| pg.bounds().ok()).map(|b| Vec2::new(b.x1 - b.x0, b.y1 - b.y0)).collect();
        self.doc = Some(d);
        self.tex.clear(); self.thumbs.clear(); self.text.clear(); self.sel = None; self.find_hits.clear(); self.find_for.clear();
    }
    pub fn save_to(&mut self, p: &str) {
        if let Some(d) = &self.doc { match ops::save(d, p, false) { Ok(_) => { self.path = p.to_string(); self.dirty = false; self.status = format!("Saved {p}"); } Err(e) => self.status = format!("Save failed: {e}") } }
    }
    fn invalidate(&mut self, page: usize) { self.tex.retain(|k, _| k.0 != page); self.thumbs.remove(&page); self.text.remove(&page); self.dirty = true; }
    fn page_tex(&mut self, ctx: &egui::Context, i: usize, scale: f32) -> Option<TextureHandle> {
        let key = (i, (scale * 100.0) as u32);
        if let Some(t) = self.tex.get(&key) { return Some(t.clone()); }
        let doc = self.doc.as_ref()?;
        let pg = doc.load_page(i as i32).ok()?;
        let pm = pg.to_pixmap(&Matrix::new_scale(scale, scale), &Colorspace::device_rgb(), false, true).ok()?;
        let img = ColorImage::from_rgb([pm.width() as usize, pm.height() as usize], pm.samples());
        let t = ctx.load_texture(format!("p{i}-{}", key.1), img, egui::TextureOptions::LINEAR);
        if self.tex.len() > 12 { let keep: Vec<_> = self.tex.keys().cloned().filter(|k| k.0 == i).collect(); self.tex.retain(|k, _| keep.contains(k)); }
        self.tex.insert(key, t.clone());
        Some(t)
    }
    fn thumb(&mut self, ctx: &egui::Context, i: usize, ppp: f32) -> Option<TextureHandle> {
        if let Some(t) = self.thumbs.get(&i) { return Some(t.clone()); }
        let doc = self.doc.as_ref()?;
        let pg = doc.load_page(i as i32).ok()?;
        let s = 0.2 * ppp;
        let pm = pg.to_pixmap(&Matrix::new_scale(s, s), &Colorspace::device_rgb(), false, true).ok()?;
        let img = ColorImage::from_rgb([pm.width() as usize, pm.height() as usize], pm.samples());
        let t = ctx.load_texture(format!("th{i}"), img, egui::TextureOptions::LINEAR);
        self.thumbs.insert(i, t.clone());
        Some(t)
    }
    pub fn page_chars(&mut self, i: usize) -> &Vec<Ch> {
        if !self.text.contains_key(&i) {
            let mut out = vec![];
            if let Some(doc) = &self.doc {
                if let Ok(pg) = doc.load_page(i as i32) {
                    if let Ok(tp) = pg.to_text_page(TextPageFlags::PRESERVE_WHITESPACE) {
                        let mut line_no = 0u32;
                        for b in tp.blocks() { for l in b.lines() {
                            for ch in l.chars() { if let Some(c) = ch.char() {
                                let r = qrect(&ch.quad());
                                out.push(Ch { c, r, line: line_no });
                            } }
                            if let Some(last) = out.last().cloned() { out.push(Ch { c: '\n', r: Rect::from_min_size(pos2(last.r.right(), last.r.top()), vec2(0.0, last.r.height())), line: line_no }); }
                            line_no += 1;
                        } }
                    }
                }
            }
            self.text.insert(i, out);
        }
        &self.text[&i]
    }
    fn hit(&mut self, i: usize, p: Pos2) -> Option<usize> {
        let ch = self.page_chars(i);
        if ch.is_empty() { return None; }
        let mut best_line = None; let mut best_d = f32::MAX;
        for c in ch.iter() { if c.c == '\n' { continue; }
            let d = if p.y < c.r.top() { c.r.top() - p.y } else if p.y > c.r.bottom() { p.y - c.r.bottom() } else { 0.0 };
            if d < best_d { best_d = d; best_line = Some(c.line); } }
        let line = best_line?;
        let mut best = None; let mut bd = f32::MAX;
        for (k, c) in ch.iter().enumerate() { if c.line != line || c.c == '\n' { continue; }
            let dx = if p.x < c.r.left() { c.r.left() - p.x } else if p.x > c.r.right() { p.x - c.r.right() } else { 0.0 };
            if dx < bd { bd = dx; best = Some(k); } }
        best
    }
    fn word_range(&mut self, i: usize, k: usize) -> (usize, usize) {
        let ch = self.page_chars(i);
        let kind = |c: char| if c.is_alphanumeric() || c == '_' { 0 } else if c.is_whitespace() { 1 } else { 2 };
        let t = kind(ch[k].c); let (mut a, mut b) = (k, k);
        while a > 0 && ch[a - 1].c != '\n' && kind(ch[a - 1].c) == t { a -= 1; }
        while b + 1 < ch.len() && ch[b + 1].c != '\n' && kind(ch[b + 1].c) == t { b += 1; }
        (a, b)
    }
    fn line_range(&mut self, i: usize, k: usize) -> (usize, usize) {
        let ch = self.page_chars(i); let l = ch[k].line;
        (ch.iter().position(|c| c.line == l).unwrap_or(k), ch.iter().rposition(|c| c.line == l && c.c != '\n').unwrap_or(k))
    }
    pub fn selected_text(&mut self) -> String {
        if let Some(s) = self.sel { let ch = self.page_chars(s.page); let hi = s.b.min(ch.len().saturating_sub(1)); return ch[s.a..=hi].iter().map(|c| c.c).collect::<String>().trim_end_matches('\n').to_string(); }
        String::new()
    }
    /// One quad per text line of the selection.
    fn sel_quads(&mut self) -> Vec<Quad> {
        let Some(s) = self.sel else { return vec![] };
        let ch = self.page_chars(s.page).clone();
        let mut out: Vec<Quad> = vec![]; let mut cur: Option<(u32, Rect)> = None;
        for c in &ch[s.a..=s.b.min(ch.len() - 1)] {
            if c.c == '\n' { continue; }
            match &mut cur { Some((l, r)) if *l == c.line => { *r = r.union(c.r); } _ => { if let Some((_, r)) = cur.take() { out.push(rq(r)); } cur = Some((c.line, c.r)); } }
        }
        if let Some((_, r)) = cur { out.push(rq(r)); }
        out
    }
    fn do_find(&mut self) {
        self.find_hits.clear(); self.find_cur = 0; self.find_for = self.find_q.clone();
        if self.find_q.is_empty() { return; }
        if let Some(d) = &self.doc {
            for i in 0..d.page_count().unwrap_or(0) {
                if let Ok(pg) = d.load_page(i) { if let Ok(tp) = pg.to_text_page(TextPageFlags::empty()) { if let Ok(qs) = tp.search(&self.find_q) { for q in qs { self.find_hits.push((i as usize, qrect(&q))); } } } }
            }
        }
        self.status = format!("{} match(es)", self.find_hits.len());
    }
    fn offsets(&self) -> Vec<f32> { let mut v = vec![]; let mut y = 12.0; for s in &self.sizes { v.push(y); y += s.y * self.zoom + 12.0; } v }
    fn goto_find(&mut self) {
        if let Some((pg, r)) = self.find_hits.get(self.find_cur).cloned() { let off = self.offsets(); self.want_scroll_to = Some(off[pg] + r.top() * self.zoom - 120.0); }
    }
    pub fn commit_text(&mut self) {
        if let Some(e) = self.edit.take() {
            let t = e.text.trim_end().to_string();
            if t.is_empty() { return; }
            let lines: Vec<&str> = t.lines().collect();
            let w = lines.iter().map(|l| l.chars().count()).max().unwrap_or(1) as f32 * 6.5 + 10.0;
            let h = lines.len() as f32 * 15.0 + 6.0;
            let r = mupdf::Rect::new(e.at.x, e.at.y, e.at.x + w, e.at.y + h);
            if let Some(d) = self.doc.as_mut() { match ops::add_freetext(d, e.page as i32, r, &t, 12.0, [0.0, 0.0, 0.0]) { Ok(_) => { self.status = "Text added".into(); } Err(er) => self.status = format!("Text failed: {er}") } }
            self.invalidate(e.page);
        }
    }

    pub fn ui(&mut self, ctx: &egui::Context) {
        let ppp = ctx.pixels_per_point();
        // shortcuts
        if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::F)) { self.show_find = true; }
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) { if self.edit.is_some() { self.edit = None; } else { self.show_find = false; self.sel = None; } }
        #[cfg(windows)]
        {
            if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::O)) { if let Some(p) = rfd::FileDialog::new().add_filter("PDF", &["pdf"]).pick_file() { self.open(&p.to_string_lossy()); } }
            if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::S)) { self.save_cmd(); }
        }
        egui::TopBottomPanel::top("bar").show(ctx, |ui| {
            ui.horizontal_wrapped(|ui| {
                #[cfg(windows)]
                {
                    if ui.button("Open").clicked() { if let Some(p) = rfd::FileDialog::new().add_filter("PDF", &["pdf"]).pick_file() { self.open(&p.to_string_lossy()); } }
                    if ui.button("Save").clicked() { self.save_cmd(); }
                    if ui.button("Save as").clicked() { if let Some(p) = rfd::FileDialog::new().add_filter("PDF", &["pdf"]).save_file() { self.save_to(&p.to_string_lossy()); } }
                    ui.separator();
                }
                for (t, n) in [(Tool::Select, "Select"), (Tool::Highlight, "Highlight"), (Tool::Underline, "Underline"), (Tool::Strike, "Strike"), (Tool::Ink, "Pen"), (Tool::Text, "Text"), (Tool::Eraser, "Eraser"), (Tool::Redact, "Redact")] {
                    if ui.selectable_label(self.tool == t, n).clicked() { self.commit_text(); self.tool = t; if t == Tool::Highlight { self.color = [1.0, 0.85, 0.0]; } if t == Tool::Ink { self.color = [0.1, 0.2, 0.9]; } }
                }
                ui.separator();
                let mut c = Color32::from_rgb((self.color[0] * 255.0) as u8, (self.color[1] * 255.0) as u8, (self.color[2] * 255.0) as u8);
                if ui.color_edit_button_srgba(&mut c).changed() { self.color = [c.r() as f32 / 255.0, c.g() as f32 / 255.0, c.b() as f32 / 255.0]; }
                if self.tool == Tool::Ink { ui.add(egui::Slider::new(&mut self.ink_width, 1.0..=12.0).text("width")); }
                if self.tool == Tool::Redact && ui.button("Apply redactions").clicked() {
                    if let Some(d) = self.doc.as_mut() { match ops::apply_all_redactions(d) { Ok(n) => self.status = format!("Applied {n} redaction(s)"), Err(e) => self.status = format!("Redact failed: {e}") } }
                    self.tex.clear(); self.thumbs.clear(); self.text.clear(); self.dirty = true;
                }
                ui.separator();
                if ui.button("Find").clicked() { self.show_find = !self.show_find; }
                ui.toggle_value(&mut self.show_thumbs, "Pages");
                ui.separator();
                ui.label(format!("{:.0}%", self.zoom * 100.0));
            });
        });
        if self.show_find {
            egui::TopBottomPanel::top("find").show(ctx, |ui| { ui.horizontal(|ui| {
                ui.label("Find:");
                let r = ui.add(egui::TextEdit::singleline(&mut self.find_q).desired_width(220.0));
                if r.changed() || self.find_for != self.find_q { self.do_find(); self.goto_find(); }
                if r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) { if !self.find_hits.is_empty() { self.find_cur = (self.find_cur + 1) % self.find_hits.len(); self.goto_find(); } r.request_focus(); }
                if ui.button("Prev").clicked() && !self.find_hits.is_empty() { self.find_cur = (self.find_cur + self.find_hits.len() - 1) % self.find_hits.len(); self.goto_find(); }
                if ui.button("Next").clicked() && !self.find_hits.is_empty() { self.find_cur = (self.find_cur + 1) % self.find_hits.len(); self.goto_find(); }
                ui.label(if self.find_hits.is_empty() { "no matches".to_string() } else { format!("{} of {}", self.find_cur + 1, self.find_hits.len()) });
            }); });
        }
        egui::TopBottomPanel::bottom("status").show(ctx, |ui| { ui.horizontal(|ui| {
            ui.label(&self.status); ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| { ui.label(format!("{} pages{}", self.sizes.len(), if self.dirty { "  (unsaved)" } else { "" })); });
        }); });
        if self.show_thumbs && !self.sizes.is_empty() {
            egui::SidePanel::left("thumbs").exact_width(120.0).resizable(false).show(ctx, |ui| {
                egui::ScrollArea::vertical().show(ui, |ui| {
                    for i in 0..self.sizes.len() {
                        if let Some(t) = self.thumb(ctx, i, ppp) {
                            let w = 96.0; let h = w * self.sizes[i].y / self.sizes[i].x;
                            let (r, resp) = ui.allocate_exact_size(vec2(w, h), egui::Sense::click());
                            ui.painter().image(t.id(), r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
                            ui.painter().rect_stroke(r, 0.0, Stroke::new(1.0, Color32::from_gray(120)), StrokeKind::Outside);
                            ui.label(format!("{}", i + 1));
                            if resp.clicked() { let off = self.offsets(); self.want_scroll_to = Some(off[i] - 12.0); }
                        }
                    }
                });
            });
        }
        egui::CentralPanel::default().frame(egui::Frame::NONE.fill(Color32::from_gray(58))).show(ctx, |ui| {
            let area = ui.available_rect_before_wrap();
            // zoom
            let zd = ui.input(|i| i.zoom_delta());
            if zd != 1.0 { let old = self.zoom; self.zoom = (self.zoom * zd).clamp(0.1, 8.0); if let Some(p) = ui.input(|i| i.pointer.hover_pos()) { let ay = p.y - area.top(); self.scroll = (self.scroll + ay) * (self.zoom / old) - ay; } }
            let resp = ui.interact(area, ui.id().with("canvas"), egui::Sense::click_and_drag());
            let sd = ui.input(|i| i.smooth_scroll_delta.y);
            self.scroll -= sd;
            if let Some(t) = self.want_scroll_to.take() { self.scroll = t; }
            let gap = 12.0;
            let total: f32 = self.sizes.iter().map(|s| s.y * self.zoom + gap).sum();
            self.scroll = self.scroll.clamp(0.0, (total - area.height()).max(0.0));
            let mut rects = vec![]; let mut y = area.top() + gap - self.scroll;
            for s in &self.sizes { let sz = *s * self.zoom; rects.push(Rect::from_min_size(pos2(area.center().x - sz.x / 2.0, y), sz)); y += sz.y + gap; }
            let z = self.zoom;
            let to_pdf = |rects: &Vec<Rect>, p: Pos2| -> Option<(usize, Pos2)> {
                let mut best = None; let mut bd = f32::MAX;
                for (i, r) in rects.iter().enumerate() { let d = if p.y < r.top() { r.top() - p.y } else if p.y > r.bottom() { p.y - r.bottom() } else { 0.0 }; if d < bd { bd = d; best = Some(i); } }
                best.map(|i| (i, pos2((p.x - rects[i].left()) / z, (p.y - rects[i].top()) / z)))
            };
            ctx.set_cursor_icon(match self.tool { Tool::Select | Tool::Highlight | Tool::Underline | Tool::Strike => egui::CursorIcon::Text, Tool::Ink | Tool::Redact => egui::CursorIcon::Crosshair, Tool::Text => egui::CursorIcon::Text, Tool::Eraser => egui::CursorIcon::NotAllowed });
            let pos = resp.interact_pointer_pos();
            let tool = self.tool;
            match tool {
                Tool::Select | Tool::Highlight | Tool::Underline | Tool::Strike => {
                    if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) {
                        if resp.triple_clicked() { if let Some(k) = self.hit(pg, pp) { let (a, b) = self.line_range(pg, k); self.sel = Some(Sel { page: pg, a, b }); } }
                        else if resp.double_clicked() { if let Some(k) = self.hit(pg, pp) { let (a, b) = self.word_range(pg, k); self.sel = Some(Sel { page: pg, a, b }); } }
                        else if resp.drag_started() || resp.clicked() { if let Some(k) = self.hit(pg, pp) { self.anchor = Some((pg, k)); self.sel = Some(Sel { page: pg, a: k, b: k }); } }
                        else if resp.dragged() { if let Some((apg, ak)) = self.anchor { if apg == pg { if let Some(k) = self.hit(pg, pp) { self.sel = Some(Sel { page: pg, a: ak.min(k), b: ak.max(k) }); } } } }
                    } }
                    if resp.drag_stopped() && matches!(tool, Tool::Highlight | Tool::Underline | Tool::Strike) && self.sel.is_some() { self.apply_markup(tool); }
                }
                Tool::Ink => {
                    if resp.drag_started() { self.ink_cur.clear(); }
                    if resp.dragged() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) { if self.ink_cur.is_empty() { self.ink_page = pg; } if pg == self.ink_page { self.ink_cur.push(pp); } } } }
                    if resp.drag_stopped() && self.ink_cur.len() > 1 {
                        let pts: Vec<(f32, f32)> = self.ink_cur.iter().map(|p| (p.x, p.y)).collect();
                        let (pg, col, w) = (self.ink_page, self.color, self.ink_width);
                        if let Some(d) = self.doc.as_mut() { if let Err(e) = ops::add_ink(d, pg as i32, vec![pts], col, w) { self.status = format!("Ink failed: {e}"); } }
                        self.invalidate(pg); self.ink_cur.clear();
                    }
                }
                Tool::Eraser => {
                    if resp.clicked() || resp.dragged() || resp.drag_started() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) {
                        let mut gone = false;
                        if let Some(d) = self.doc.as_mut() { gone = ops::erase_at(d, pg as i32, Point::new(pp.x, pp.y), 5.0 / z.max(0.5)).unwrap_or(false); }
                        if gone { self.invalidate(pg); self.status = "Erased".into(); }
                    } } }
                }
                Tool::Text => {
                    if resp.clicked() && self.edit.is_none() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) { self.edit = Some(TextEditState { page: pg, at: pp, text: String::new(), fresh: true }); } } }
                    else if resp.clicked() && self.edit.is_some() { self.commit_text(); }
                }
                Tool::Redact => {
                    if resp.drag_started() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) { self.redact_start = Some((pg, pp)); } } }
                    if resp.dragged() { if let (Some(pos), Some((pg, _))) = (pos, self.redact_start) { let p = pos; let r = rects[pg]; self.redact_cur = Some(pos2((p.x - r.left()) / z, (p.y - r.top()) / z)); } }
                    if resp.drag_stopped() { if let (Some((pg, a)), Some(b)) = (self.redact_start.take(), self.redact_cur.take()) {
                        let r = mupdf::Rect::new(a.x.min(b.x), a.y.min(b.y), a.x.max(b.x), a.y.max(b.y));
                        if (r.x1 - r.x0) > 2.0 && (r.y1 - r.y0) > 2.0 { if let Some(d) = self.doc.as_mut() { if let Err(e) = ops::mark_redact(d, pg as i32, r) { self.status = format!("Mark failed: {e}"); } else { self.status = "Marked for redaction (press Apply redactions)".into(); } } self.invalidate(pg); }
                    } }
                }
            }
            // copy / select all
            let copy = ui.input(|i| i.events.iter().any(|e| matches!(e, egui::Event::Copy)) || (i.modifiers.command && i.key_pressed(egui::Key::C)));
            if copy { let t = self.selected_text(); if !t.is_empty() { ctx.copy_text(t.clone()); self.copied = t; self.status = "Copied".into(); } }
            if ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::A)) { if let Some((pg, _)) = to_pdf(&rects, area.center()) { let n = self.page_chars(pg).len(); if n > 0 { self.sel = Some(Sel { page: pg, a: 0, b: n - 1 }); } } }
            // paint
            let painter = ui.painter_at(area);
            for i in 0..self.sizes.len() {
                let r = rects[i];
                if !(r.bottom() >= area.top() && r.top() <= area.bottom()) { continue; }
                painter.rect_filled(r.translate(Vec2::splat(2.0)), 0.0, Color32::from_black_alpha(80));
                if let Some(t) = self.page_tex(ctx, i, self.zoom * ppp) { painter.image(t.id(), r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE); }
                if let Some(s) = self.sel { if s.page == i { let ch = self.page_chars(i).clone(); for c in &ch[s.a..=s.b.min(ch.len() - 1)] { if c.c == '\n' { continue; } painter.rect_filled(Rect::from_min_max(r.min + c.r.min.to_vec2() * z, r.min + c.r.max.to_vec2() * z), 0.0, Color32::from_rgba_unmultiplied(40, 110, 255, 90)); } } }
                for (k, (pg, hr)) in self.find_hits.iter().enumerate() { if *pg == i { let col = if k == self.find_cur { Color32::from_rgba_unmultiplied(255, 120, 0, 150) } else { Color32::from_rgba_unmultiplied(255, 220, 0, 110) }; painter.rect_filled(Rect::from_min_max(r.min + hr.min.to_vec2() * z, r.min + hr.max.to_vec2() * z), 0.0, col); } }
                if tool == Tool::Ink && self.ink_page == i && self.ink_cur.len() > 1 {
                    let c = Color32::from_rgb((self.color[0] * 255.0) as u8, (self.color[1] * 255.0) as u8, (self.color[2] * 255.0) as u8);
                    let pts: Vec<Pos2> = self.ink_cur.iter().map(|p| r.min + p.to_vec2() * z).collect();
                    painter.add(egui::Shape::line(pts, Stroke::new(self.ink_width * z, c)));
                }
                if let (Some((pg, a)), Some(b)) = (self.redact_start, self.redact_cur) { if pg == i { painter.rect_stroke(Rect::from_two_pos(r.min + a.to_vec2() * z, r.min + b.to_vec2() * z), 0.0, Stroke::new(2.0, Color32::RED), StrokeKind::Middle); } }
            }
            // on-page text box
            if let Some(e) = &mut self.edit {
                let r = rects[e.page];
                let at = r.min + e.at.to_vec2() * z;
                let mut commit = false;
                egui::Area::new(egui::Id::new("ftext")).fixed_pos(at).order(egui::Order::Foreground).show(ctx, |ui| {
                    egui::Frame::NONE.stroke(Stroke::new(1.0, Color32::from_rgb(40, 110, 255))).fill(Color32::from_white_alpha(230)).show(ui, |ui| {
                        let te = egui::TextEdit::multiline(&mut e.text).font(FontId::proportional(12.0 * z)).text_color(Color32::BLACK).desired_width(220.0 * z.max(0.6)).desired_rows(1).frame(egui::Frame::NONE);
                        let rr = ui.add(te);
                        if e.fresh { rr.request_focus(); e.fresh = false; }
                        if rr.lost_focus() && !ui.input(|i| i.key_pressed(egui::Key::Escape)) { commit = true; }
                    });
                });
                if commit { self.commit_text(); }
            }
            let _ = (Align2::CENTER_CENTER,);
        });
    }
    #[cfg(windows)]
    fn save_cmd(&mut self) { if self.path.is_empty() { if let Some(p) = rfd::FileDialog::new().add_filter("PDF", &["pdf"]).save_file() { self.save_to(&p.to_string_lossy()); } } else { let p = self.path.clone(); self.save_to(&p); } }
    fn apply_markup(&mut self, tool: Tool) {
        let quads = self.sel_quads();
        if quads.is_empty() { return; }
        let pg = self.sel.unwrap().page;
        let kind = match tool { Tool::Highlight => 0, Tool::Underline => 1, _ => 2 };
        let col = self.color;
        if let Some(d) = self.doc.as_mut() { match ops::add_markup(d, pg as i32, kind, quads, col) { Ok(_) => self.status = "Markup added".into(), Err(e) => self.status = format!("Markup failed: {e}") } }
        self.sel = None; self.invalidate(pg);
    }
}

fn rq(r: Rect) -> Quad { Quad::new(Point::new(r.left(), r.top()), Point::new(r.right(), r.top()), Point::new(r.left(), r.bottom()), Point::new(r.right(), r.bottom())) }
EOF
python3 - <<'EOF'
p='/tmp/scratch/app/src/main.rs'; s=open(p).read()
s=s.replace("mod app;","mod ops;\nmod app;")
open(p,'w').write(s)
p='/tmp/scratch/app/Cargo.toml'; s=open(p).read()
if 'rfd' not in s: s+='\n[target.\'cfg(windows)\'.dependencies]\nrfd = { version = "0.15", default-features = false }\n'
open(p,'w').write(s)
EOF
sed -i 's|#\[path = "/tmp/scratch/app/src/app.rs"\]|#[path = "/tmp/scratch/app/src/ops.rs"]\nmod ops;\n#[path = "/tmp/scratch/app/src/app.rs"]|' /tmp/scratch/shot/src/main.rs; head -6 /tmp/scratch/shot/src/main.rs
echo "11:40 app.rs v2 written (tools UI) + ops extra fns; compiling" >> ~/NOTES_native.md
cd /tmp/scratch/shot; source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin shot 2>&1 | grep -E "^error" -A7 | head -70 | cut -c1-170)
