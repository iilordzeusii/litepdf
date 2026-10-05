cd /tmp/scratch/app/src && cat > app.rs <<'EOF'
use egui::{self, Color32, ColorImage, Pos2, Rect, TextureHandle, Vec2, pos2, vec2};
use mupdf::{Colorspace, Document, Matrix, TextPageFlags};
use std::collections::HashMap;

#[derive(Clone)]
pub struct Ch { pub c: char, pub r: Rect, pub line: u32 }

#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Sel { pub page: usize, pub a: usize, pub b: usize } // inclusive char range a..=b (a<=b)

pub struct App {
    pub doc: Option<Document>,
    pub sizes: Vec<Vec2>,
    pub tex: HashMap<(usize, u32), TextureHandle>,
    pub text: HashMap<usize, Vec<Ch>>,
    pub zoom: f32,
    pub scroll: f32,
    pub path: String,
    pub sel: Option<Sel>,
    anchor: Option<(usize, usize)>,
    pub copied: String,
}

impl App {
    pub fn new() -> Self {
        App { doc: None, sizes: vec![], tex: HashMap::new(), text: HashMap::new(), zoom: 1.0, scroll: 0.0, path: String::new(), sel: None, anchor: None, copied: String::new() }
    }
    pub fn open(&mut self, p: &str) {
        if let Ok(d) = Document::open(p) {
            let n = d.page_count().unwrap_or(0);
            self.sizes = (0..n).filter_map(|i| d.load_page(i).ok()).filter_map(|pg| pg.bounds().ok()).map(|b| Vec2::new(b.x1 - b.x0, b.y1 - b.y0)).collect();
            self.doc = Some(d);
            self.tex.clear();
            self.text.clear();
            self.sel = None;
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
    /// Characters of a page in reading order, with boxes in PDF points.
    pub fn page_chars(&mut self, i: usize) -> &Vec<Ch> {
        if !self.text.contains_key(&i) {
            let mut out = vec![];
            if let Some(doc) = &self.doc {
                if let Ok(pg) = doc.load_page(i as i32) {
                    if let Ok(tp) = pg.to_text_page(TextPageFlags::PRESERVE_WHITESPACE) {
                        let mut line_no = 0u32;
                        for b in tp.blocks() {
                            for l in b.lines() {
                                for ch in l.chars() {
                                    if let Some(c) = ch.char() {
                                        let q = ch.quad();
                                        let xs = [q.ul.x, q.ur.x, q.ll.x, q.lr.x];
                                        let ys = [q.ul.y, q.ur.y, q.ll.y, q.lr.y];
                                        let x0 = xs.iter().cloned().fold(f32::MAX, f32::min);
                                        let x1 = xs.iter().cloned().fold(f32::MIN, f32::max);
                                        let y0 = ys.iter().cloned().fold(f32::MAX, f32::min);
                                        let y1 = ys.iter().cloned().fold(f32::MIN, f32::max);
                                        out.push(Ch { c, r: Rect::from_min_max(pos2(x0, y0), pos2(x1, y1)), line: line_no });
                                    }
                                }
                                // line break marker
                                if let Some(last) = out.last().cloned() { out.push(Ch { c: '\n', r: Rect::from_min_size(pos2(last.r.right(), last.r.top()), vec2(0.0, last.r.height())), line: line_no }); }
                                line_no += 1;
                            }
                        }
                    }
                }
            }
            self.text.insert(i, out);
        }
        &self.text[&i]
    }
    /// Nearest character index to a point (PDF points) on a page.
    fn hit(&mut self, i: usize, p: Pos2) -> Option<usize> {
        let ch = self.page_chars(i);
        if ch.is_empty() { return None; }
        // choose the line whose vertical band is closest, then the char in it
        let mut best_line = None; let mut best_d = f32::MAX;
        for c in ch.iter() {
            if c.c == '\n' { continue; }
            let d = if p.y < c.r.top() { c.r.top() - p.y } else if p.y > c.r.bottom() { p.y - c.r.bottom() } else { 0.0 };
            if d < best_d { best_d = d; best_line = Some(c.line); }
        }
        let line = best_line?;
        let mut best = None; let mut bd = f32::MAX;
        for (k, c) in ch.iter().enumerate() {
            if c.line != line || c.c == '\n' { continue; }
            let dx = if p.x < c.r.left() { c.r.left() - p.x } else if p.x > c.r.right() { p.x - c.r.right() } else { 0.0 };
            if dx < bd { bd = dx; best = Some(k); }
        }
        best
    }
    fn word_range(&mut self, i: usize, k: usize) -> (usize, usize) {
        let ch = self.page_chars(i);
        let is_w = |c: char| c.is_alphanumeric() || c == '_' ;
        let kind = |c: char| if is_w(c) { 0 } else if c.is_whitespace() { 1 } else { 2 };
        let t = kind(ch[k].c);
        let (mut a, mut b) = (k, k);
        while a > 0 && ch[a - 1].c != '\n' && kind(ch[a - 1].c) == t { a -= 1; }
        while b + 1 < ch.len() && ch[b + 1].c != '\n' && kind(ch[b + 1].c) == t { b += 1; }
        (a, b)
    }
    fn line_range(&mut self, i: usize, k: usize) -> (usize, usize) {
        let ch = self.page_chars(i);
        let l = ch[k].line;
        let a = ch.iter().position(|c| c.line == l).unwrap_or(k);
        let b = ch.iter().rposition(|c| c.line == l && c.c != '\n').unwrap_or(k);
        (a, b)
    }
    pub fn selected_text(&mut self) -> String {
        if let Some(s) = self.sel {
            let ch = self.page_chars(s.page);
            let hi = s.b.min(ch.len().saturating_sub(1));
            return ch[s.a..=hi].iter().map(|c| c.c).collect::<String>().trim_end_matches('\n').to_string();
        }
        String::new()
    }

    pub fn ui(&mut self, ctx: &egui::Context) {
        let ppp = ctx.pixels_per_point();
        egui::TopBottomPanel::top("bar").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.heading("LitePDF");
                ui.label(format!("{}  |  {:.0}%  |  {} pages", self.path, self.zoom * 100.0, self.sizes.len()));
                if let Some(s) = self.sel { ui.label(format!("selected {} chars", s.b - s.a + 1)); }
            });
        });
        egui::CentralPanel::default().frame(egui::Frame::NONE.fill(Color32::from_gray(60))).show(ctx, |ui| {
            let zd = ui.input(|i| i.zoom_delta());
            if zd != 1.0 { self.zoom = (self.zoom * zd).clamp(0.1, 8.0); }
            let area = ui.available_rect_before_wrap();
            let resp = ui.interact(area, ui.id().with("canvas"), egui::Sense::click_and_drag());
            let sd = ui.input(|i| i.smooth_scroll_delta.y);
            self.scroll -= sd;
            let gap = 12.0;
            let total: f32 = self.sizes.iter().map(|s| s.y * self.zoom + gap).sum();
            self.scroll = self.scroll.clamp(0.0, (total - area.height()).max(0.0));
            // page layout rects
            let mut rects = vec![]; let mut y = area.top() + gap - self.scroll;
            for s in &self.sizes { let sz = *s * self.zoom; rects.push(Rect::from_min_size(pos2(area.center().x - sz.x / 2.0, y), sz)); y += sz.y + gap; }
            // pointer -> (page, pdf point)
            let to_pdf = |rects: &Vec<Rect>, p: Pos2, z: f32| -> Option<(usize, Pos2)> {
                // nearest page by vertical distance
                let mut best = None; let mut bd = f32::MAX;
                for (i, r) in rects.iter().enumerate() {
                    let d = if p.y < r.top() { r.top() - p.y } else if p.y > r.bottom() { p.y - r.bottom() } else { 0.0 };
                    if d < bd { bd = d; best = Some(i); }
                }
                best.map(|i| (i, pos2((p.x - rects[i].left()) / z, (p.y - rects[i].top()) / z)))
            };
            if resp.hovered() { ctx.set_cursor_icon(egui::CursorIcon::Text); }
            if let Some(pos) = resp.interact_pointer_pos() {
                if let Some((pg, pp)) = to_pdf(&rects, pos, self.zoom) {
                    if resp.triple_clicked() {
                        if let Some(k) = self.hit(pg, pp) { let (a, b) = self.line_range(pg, k); self.sel = Some(Sel { page: pg, a, b }); }
                    } else if resp.double_clicked() {
                        if let Some(k) = self.hit(pg, pp) { let (a, b) = self.word_range(pg, k); self.sel = Some(Sel { page: pg, a, b }); }
                    } else if resp.drag_started() || resp.clicked() {
                        if let Some(k) = self.hit(pg, pp) { self.anchor = Some((pg, k)); self.sel = Some(Sel { page: pg, a: k, b: k }); }
                    } else if resp.dragged() {
                        if let Some((apg, ak)) = self.anchor {
                            if apg == pg { if let Some(k) = self.hit(pg, pp) { self.sel = Some(Sel { page: pg, a: ak.min(k), b: ak.max(k) }); } }
                        }
                    }
                }
            }
            let copy = ui.input(|i| i.events.iter().any(|e| matches!(e, egui::Event::Copy)) || (i.modifiers.command && i.key_pressed(egui::Key::C)));
            if copy { let t = self.selected_text(); if !t.is_empty() { ctx.copy_text(t.clone()); self.copied = t; } }
            if ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::A)) {
                if let Some((pg, _)) = to_pdf(&rects, area.center(), self.zoom) { let n = self.page_chars(pg).len(); if n > 0 { self.sel = Some(Sel { page: pg, a: 0, b: n - 1 }); } }
            }
            let painter = ui.painter_at(area);
            for i in 0..self.sizes.len() {
                let r = rects[i];
                if r.bottom() >= area.top() && r.top() <= area.bottom() {
                    painter.rect_filled(r.translate(Vec2::splat(2.0)), 0.0, Color32::from_black_alpha(80));
                    if let Some(t) = self.page_tex(ctx, i, self.zoom * ppp) {
                        painter.image(t.id(), r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
                    }
                    if let Some(s) = self.sel { if s.page == i {
                        let z = self.zoom; let ch = self.page_chars(i).clone();
                        for c in &ch[s.a..=s.b.min(ch.len() - 1)] {
                            if c.c == '\n' { continue; }
                            let cr = Rect::from_min_max(r.min + c.r.min.to_vec2() * z, r.min + c.r.max.to_vec2() * z);
                            painter.rect_filled(cr, 0.0, Color32::from_rgba_unmultiplied(40, 110, 255, 90));
                        }
                    } }
                }
            }
        });
    }
}
EOF
python3 - <<'EOF'
p='/tmp/scratch/app/src/main.rs'; s=open(p).read()
import re
s=re.sub(r"let mut app = App \{[^}]*\};","let mut app = App::new();",s)
open(p,'w').write(s)
p='/tmp/scratch/shot/src/main.rs'; s=open(p).read()
s=re.sub(r"let mut app = App \{[^}]*\};","let mut app = App::new();",s)
s=s.replace("app.open(pdf);","app.open(pdf);\n    if let Some(sx)=a.get(4){ let v:Vec<usize>=sx.split(',').map(|x|x.parse().unwrap()).collect(); app.sel=Some(app::Sel{page:0,a:v[0],b:v[1]}); }")
open(p,'w').write(s)
EOF
grep -n "App" main.rs | head; cd ../../shot; source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release 2>&1 | grep -E "^error|Finished" -A9 | head -40 | cut -c1-180)
