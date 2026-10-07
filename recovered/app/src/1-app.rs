use crate::{ops, extras, render, dm};
use crate::render::{Cmd, Src, Res, Job, Kind, Worker};
use std::sync::mpsc::{channel, Receiver, Sender};
use egui::{self, Align2, Color32, ColorImage, FontId, Pos2, Rect, Stroke, StrokeKind, TextureHandle, Vec2, pos2, vec2};
use mupdf::pdf::PdfDocument;
use mupdf::{Colorspace, Matrix, Point, Quad, TextPageFlags};
use std::collections::{HashMap, HashSet};

#[derive(Clone)]
pub struct Ch { pub c: char, pub r: Rect, pub line: u32 }
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Sel { pub page: usize, pub a: usize, pub b: usize }
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Tool { Select, Highlight, Underline, Strike, Ink, Text, Eraser, Redact, Sign }

pub enum Msg { Status(String), Note(String), Reload(u32, String, String), Ai(Result<String, String>) }
#[derive(PartialEq, Clone, Copy)]
pub enum Dlg { None, Split, Compress, Protect, Sign, Password, Merge, Ocr, CloseTab(usize) }
pub struct TextEditState { pub page: usize, pub at: Pos2, pub text: String, pub fresh: bool, pub idx: Option<usize>, pub font: usize, pub size: f32, pub color: [f32; 3], pub w: f32 }

#[derive(Clone, Debug)]
pub enum LinkT { Page(usize, Option<f32>), Uri(String) }

pub struct App {
    pub doc: Option<PdfDocument>,
    pub links: HashMap<usize, Vec<(mupdf::Rect, LinkT)>>,
    pub sizes: Vec<Vec2>,
    pub view: DocView,
    pub worker: Option<Worker>,
    pub frame: u64,
    pub tabs: Vec<Option<DocState>>, pub active: usize, pub next_tab: u32,
    pub last_sent: HashSet<Job>, pub want_bases: HashSet<usize>, pub doc_pw: Option<String>,
    pub perf: Perf, pub prev_scroll: f32, pub scroll_vel: f32,
    pub diag: Diag, pub notch: f32, pub sanim: Option<(f32, f32, std::time::Instant)>, pub zanim: Option<(f32, f32, std::time::Instant)>, pub sanim2: Option<ScrollAnim>, pub zrem: f32, pub ztarget: f32, pub zlast: f32, pub tvel: f32, pub tsamp: Vec<(std::time::Instant, f32)>, pub tlast: std::time::Instant, pub miss_frame: usize, pub miss_last: usize, pub last_res: std::time::Instant, pub watchdog: u32, pub mrem: f32, pub swipe: Option<Swipe>, pub gl_finish: std::sync::Arc<std::sync::atomic::AtomicBool>,
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
    pub settings: extras::Settings,
    pub show_ai: bool, pub ai_prompt: String, pub ai_out: String, pub ai_busy: bool,
    pub ai_use_text: bool, pub ai_use_image: bool, pub ai_scope_doc: bool, pub ai_mode: u8, pub ai_from: String, pub ai_to: String,
    pub tx: Sender<Msg>, pub rx: Receiver<Msg>,
    pub dlg: Dlg, pub f1: String, pub f2: String, pub f3: String, pub quality: f32, pub perm_print: bool, pub perm_copy: bool, pub perm_edit: bool,
    pub pending: Option<PdfDocument>, pub pending_path: String,
    pub form_edit: Option<(usize, ops::Field, String)>,
    pub cur_page: usize, pub ocr_force: bool, pub comp_dpi: f32, pub goto: String, pub last_title: String,
    pub busy: String,
    pub view_w: f32, pub chat: Vec<(bool, String)>, pub chat_input: String,
    pub sign_box: Option<(usize, mupdf::Rect)>, pub sign_strokes: Vec<Vec<Pos2>>, pub sign_cur: Vec<Pos2>, pub sign_start: Option<(usize, Pos2)>, pub sign_drag: Option<Pos2>,
    pub zoom_t: std::time::Instant, pub styled: bool, pub font: usize, pub fsize: f32, pub ocr_log_hint: String,
}

fn qrect(q: &Quad) -> Rect { let r = ops::quad_rect(q); Rect::from_min_max(pos2(r.x0, r.y0), pos2(r.x1, r.y1)) }

impl App {
    pub fn new() -> Self {
        if let Ok(rd) = std::fs::read_dir(std::env::temp_dir()) { for e in rd.flatten() { let n = e.file_name().to_string_lossy().to_string(); if n.starts_with("litepdf-") && (n.ends_with(".pdf") || n.ends_with(".bmp") || n.ends_with(".json")) { let _ = std::fs::remove_file(e.path()); } } }
        let (tx, rx) = channel();
        App { doc: None, links: HashMap::new(), sizes: vec![], view: DocView::new(1, 0), worker: None, frame: 0, tabs: vec![None], active: 0, next_tab: 2, last_sent: HashSet::new(), want_bases: HashSet::new(), doc_pw: None, perf: Perf::new(), prev_scroll: 0.0, scroll_vel: 0.0, diag: Diag::default(), notch: 0.0, sanim: None, zanim: None, sanim2: None, zrem: 0.0, ztarget: 0.0, zlast: 1.0, tvel: 0.0, tsamp: Vec::new(), tlast: std::time::Instant::now(), miss_frame: 0, miss_last: 0, last_res: std::time::Instant::now(), watchdog: 0, mrem: 0.0, swipe: None, gl_finish: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)), text: HashMap::new(), zoom: 1.0, scroll: 0.0, path: String::new(), dirty: false, sel: None, anchor: None, copied: String::new(),
            tool: Tool::Select, color: [0.0, 0.0, 0.0], ink_width: 2.0, ink_cur: vec![], ink_page: 0, redact_start: None, redact_cur: None, edit: None,
            settings: extras::load_settings(), show_ai: false, ai_prompt: String::new(), ai_out: String::new(), ai_busy: false, ai_use_text: true, ai_use_image: false, ai_scope_doc: false, ai_mode: 0, ai_from: "1".into(), ai_to: String::new(), tx, rx, dlg: Dlg::None, f1: String::new(), f2: String::new(), f3: String::new(), quality: 70.0, perm_print: true, perm_copy: true, perm_edit: false, view_w: 900.0, chat: vec![], chat_input: String::new(), sign_box: None, sign_strokes: vec![], sign_cur: vec![], sign_start: None, sign_drag: None, zoom_t: std::time::Instant::now(), styled: false, font: 0, fsize: 12.0, ocr_log_hint: String::new(), pending: None, pending_path: String::new(), form_edit: None, cur_page: 0, ocr_force: false, comp_dpi: 150.0, goto: String::new(), last_title: String::new(), busy: String::new(),
            show_find: false, find_q: String::new(), find_hits: vec![], find_cur: 0, find_for: String::new(), status: String::new(), show_thumbs: true, want_scroll_to: None }
    }
    pub fn open(&mut self, p: &str) {
        if let Some(i) = self.find_tab(p) { self.switch_to(i); return; }
        match PdfDocument::open(p) {
            Ok(d) => {
                if self.doc.is_some() { self.new_tab_blank(); }
                if d.needs_password().unwrap_or(false) { self.pending = Some(d); self.pending_path = p.to_string(); self.f1.clear(); self.dlg = Dlg::Password; return; }
                self.set_doc_src(d, Some(p.to_string())); self.path = p.to_string(); self.dirty = false; self.status = format!("Opened {p}"); }
            Err(e) => self.status = format!("Open failed: {e}"),
        }
    }
    pub fn set_doc(&mut self, d: PdfDocument) { self.set_doc_src(d, None) }
    pub fn set_doc_src(&mut self, d: PdfDocument, path: Option<String>) {
        let n = d.page_count().unwrap_or(0).max(0) as usize;
        let s0 = d.load_page(0).ok().and_then(|p| p.bounds().ok()).map(|b| Vec2::new(b.x1 - b.x0, b.y1 - b.y0)).unwrap_or(vec2(595.0, 842.0));
        self.sizes = vec![s0; n];
        let pw = self.doc_pw.take();
        let src = match path { Some(p) => Src::Path(p), None => { let mut buf: Vec<u8> = vec![]; let _ = d.write_to(&mut buf); Src::Bytes(std::sync::Arc::new(buf)) } };
        self.doc = Some(d);
        self.links.clear(); self.text.clear(); self.sel = None; self.find_hits.clear(); self.find_for.clear();
        let epoch = self.view.epoch + 1; let tab = self.view.tab;
        self.view = DocView::new(tab, epoch); self.view.pw = pw.clone();
        self.last_sent.clear();
        self.worker().send(Cmd::Open { tab, epoch, rev: 0, src, pw, want_sizes: true });
    }
    pub fn worker(&mut self) -> &Worker { if self.worker.is_none() { self.worker = Some(Worker::new()); } self.worker.as_ref().unwrap() }
    pub fn save_to(&mut self, p: &str) {
        self.save_inplace(p);
    }
    pub fn invalidate(&mut self, page: usize) {
        self.text.remove(&page); self.links.remove(&page); self.dirty = true;
        let pr = self.view.rev + 1; self.view.page_rev.insert(page, pr);
        self.view.refresh_due = Some(std::time::Instant::now());
    }
    fn invalidate_all(&mut self) {
        self.text.clear(); self.links.clear(); self.dirty = true;
        self.view.rev_all = self.view.rev + 1;
        self.view.refresh_due = Some(std::time::Instant::now());
    }
    #[cfg(windows)]
    pub fn page_links(&mut self, i: usize) -> &Vec<(mupdf::Rect, LinkT)> {
        if !self.links.contains_key(&i) {
            let mut out = vec![];
            if let Some(doc) = &self.doc {
                if let Ok(pg) = doc.load_page(i as i32) {
                    if let Ok(it) = pg.links() {
                        for l in it {
                            let d = l.dest.or_else(|| doc.resolve_link(&l.uri).ok().flatten());
                            if let Some(d) = d {
                                use mupdf::DestinationKind as K;
                                let y = match d.kind { K::FitH { top } | K::FitBH { top } => top, K::XYZ { top, .. } => top, K::FitR { top, .. } => Some(top), _ => None };
                                out.push((l.bounds, LinkT::Page(d.loc.page_number as usize, y)));
                            } else if !l.uri.is_empty() { out.push((l.bounds, LinkT::Uri(l.uri.clone()))); }
                        }
                    }
                }
            }
            self.links.insert(i, out);
        }
        &self.links[&i]
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

    pub fn ui(&mut self, ctx: &egui::Context) {
        let t0 = std::time::Instant::now();
        self.miss_frame = 0;
        self.ui_inner(ctx);
        self.miss_last = self.miss_frame;
        // watchdog: visible tiles are missing but nothing has arrived for a while -> resend the whole request list
        if self.miss_last > 0 && self.last_res.elapsed().as_millis() > 400 && self.doc.is_some() { self.last_res = std::time::Instant::now(); self.last_sent.clear(); self.watchdog += 1; if self.watchdog <= 50 { self.perf.note(format!("WATCHDOG: {} visible tiles still missing with no results for 400 ms, resending the request list", self.miss_last)); } ctx.request_repaint(); }
        let act = self.perf.active || ctx.input(|i| i.pointer.delta() != egui::Vec2::ZERO || !i.events.is_empty() || i.pointer.any_down());
        if act { self.perf.last_act = t0; }
        self.perf.frame(t0, self.view.bytes, self.view.tile_count(), self.last_sent.len());
        if self.diag.overlay {
            let (ms, gap) = (self.perf.last_ms, self.perf.last_gap);
            egui::Area::new(egui::Id::new("perf_overlay")).fixed_pos(pos2(8.0, 64.0)).order(egui::Order::Debug).interactable(false).show(ctx, |ui| {
                egui::Frame::NONE.fill(Color32::from_black_alpha(190)).corner_radius(4.0).inner_margin(6.0).show(ui, |ui| {
                    let col = if gap > 20.0 { Color32::from_rgb(255, 120, 90) } else { Color32::from_rgb(140, 230, 140) };
                    ui.label(egui::RichText::new(format!("frame {ms:.1} ms | gap {gap:.1} ms | {:.0} fps", 1000.0 / gap.max(0.1))).monospace().color(col));
                    ui.label(egui::RichText::new(format!("tiles {} | mem {} MB | queue {}", self.view.tile_count(), self.view.bytes >> 20, self.last_sent.len())).monospace().color(Color32::WHITE));
                });
            });
        }
        // draw every display refresh while anything is happening, plus a short tail; never wait on a timer
        if self.perf.last_act.elapsed().as_millis() < 500 { ctx.request_repaint(); }
    }
    fn ui_inner(&mut self, ctx: &egui::Context) {
        let ppp = ctx.pixels_per_point();
        self.frame += 1;
        if self.worker.is_none() { self.worker(); }
        if let Some(w) = &self.worker { if let Ok(mut g) = w.ctx.lock() { if g.is_none() { *g = Some(ctx.clone()); } } }
        self.perf.begin(); self.poll();
        self.poll_render(ctx);
        self.perf.mark("poll");
        self.refresh_worker(ctx);
        self.perf.mark("refresh");
        // tab shortcuts (consumed first so egui focus navigation does not eat Ctrl+Tab)
        let (next, prev, closew) = ctx.input_mut(|i| (i.consume_key(egui::Modifiers::COMMAND, egui::Key::Tab), i.consume_key(egui::Modifiers::COMMAND | egui::Modifiers::SHIFT, egui::Key::Tab), i.consume_key(egui::Modifiers::COMMAND, egui::Key::W)));
        let nt = self.tabs.len();
        if next && nt > 1 { let i = (self.active + 1) % nt; self.switch_to(i); }
        if prev && nt > 1 { let i = (self.active + nt - 1) % nt; self.switch_to(i); }
        if closew && self.doc.is_some() { let i = self.active; self.request_close(i); }
        let dropped: Vec<String> = ctx.input(|i| i.raw.dropped_files.iter().filter_map(|f| f.path.as_ref().map(|p| p.to_string_lossy().into_owned())).collect());
        for p in dropped { if p.to_lowercase().ends_with(".pdf") { self.open(&p); } }
        if !self.busy.is_empty() { ctx.request_repaint_after(std::time::Duration::from_millis(200)); }
        if self.ai_busy { ctx.request_repaint_after(std::time::Duration::from_millis(200)); }
        // shortcuts
        if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::F)) { self.show_find = true; }
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) { if self.edit.is_some() { self.edit = None; } else { self.show_find = false; self.sel = None; } }
        #[cfg(windows)]
        {
            if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::O)) { if let Some(p) = rfd::FileDialog::new().add_filter("PDF", &["pdf"]).pick_file() { self.open(&p.to_string_lossy()); } }
            if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::S)) { self.save_cmd(); }
        }
        if !self.styled {
            self.styled = true;
            let mut st = (*ctx.style()).clone();
            st.spacing.item_spacing = vec2(6.0, 6.0); st.spacing.button_padding = vec2(10.0, 5.0); st.spacing.interact_size.y = 28.0;
            let r = egui::CornerRadius::same(6);
            st.visuals.widgets.inactive.corner_radius = r; st.visuals.widgets.hovered.corner_radius = r; st.visuals.widgets.active.corner_radius = r; st.visuals.widgets.open.corner_radius = r;
            st.visuals.selection.bg_fill = Color32::from_rgb(45, 105, 220);
            st.visuals.widgets.inactive.weak_bg_fill = Color32::from_gray(52); st.visuals.widgets.hovered.weak_bg_fill = Color32::from_gray(70);
            st.visuals.panel_fill = Color32::from_gray(30);
            ctx.set_style(st);
        }
        {
            let name = if self.path.is_empty() { "Untitled".to_string() } else { std::path::Path::new(&self.path).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default() };
            let title = format!("{}{} - LitePDF (build b13)", name, if self.dirty { " *" } else { "" });
            if title != self.last_title { ctx.send_viewport_cmd(egui::ViewportCommand::Title(title.clone())); self.last_title = title; }
        }
        egui::TopBottomPanel::top("bar").frame(egui::Frame::NONE.fill(Color32::from_gray(36)).inner_margin(egui::Margin::symmetric(8, 6)).stroke(Stroke::new(1.0, Color32::from_gray(20)))).show(ctx, |ui| {
            ui.horizontal(|ui| {
                self.menus(ui);
                if self.doc.is_some() {
                    let nm = if self.path.is_empty() { "Untitled".to_string() } else { std::path::Path::new(&self.path).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default() };
                    let short: String = if nm.chars().count() > 26 { format!("{}...", nm.chars().take(24).collect::<String>()) } else { nm.clone() };
                    ui.add_space(4.0); ui.label(egui::RichText::new(format!("{}{}", short, if self.dirty { " *" } else { "" })).strong().size(13.5)).on_hover_text(if self.path.is_empty() { nm } else { self.path.clone() });
                }
                ui.add_space(6.0); ui.separator(); ui.add_space(6.0);
                let tools = [(Tool::Select, "Select"), (Tool::Highlight, "Highlight"), (Tool::Underline, "Underline"), (Tool::Strike, "Strike"), (Tool::Ink, "Pen"), (Tool::Text, "Text"), (Tool::Eraser, "Eraser"), (Tool::Redact, "Redact"), (Tool::Sign, "Sign")];
                egui::Frame::NONE.fill(Color32::from_gray(26)).corner_radius(8.0).inner_margin(egui::Margin::symmetric(4, 2)).show(ui, |ui| { ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 6.0; ui.spacing_mut().button_padding = vec2(9.0, 4.0);
                    for (t, n) in tools {
                        let b = egui::Button::new(egui::RichText::new(n).size(13.5)).selected(self.tool == t).frame(self.tool == t).min_size(vec2(0.0, 26.0));
                        if ui.add(b).clicked() { self.commit_text(); self.tool = t; }
                    }
                }); });
                ui.add_space(6.0);
                let mut c = Color32::from_rgb((self.color[0] * 255.0) as u8, (self.color[1] * 255.0) as u8, (self.color[2] * 255.0) as u8);
                if ui.color_edit_button_srgba(&mut c).changed() { self.color = [c.r() as f32 / 255.0, c.g() as f32 / 255.0, c.b() as f32 / 255.0]; }
                if self.tool == Tool::Ink { ui.add(egui::Slider::new(&mut self.ink_width, 1.0..=12.0).text("width")); }
                if self.tool == Tool::Redact && ui.button("Apply redactions").clicked() {
                    if let Some(d) = self.doc.as_mut() { match ops::apply_all_redactions(d) { Ok(n) => self.status = format!("Applied {n} redaction(s)"), Err(e) => self.status = format!("Redact failed: {e}") } }
                    self.invalidate_all();
                }
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if ui.button("Fit").on_hover_text("Fit page width").clicked() { if let Some(s) = self.sizes.get(self.cur_page) { self.zoom = ((self.view_w - 40.0) / s.x).clamp(0.1, 8.0); self.zoom_t = std::time::Instant::now(); } }
                    if ui.button("+").clicked() { self.zoom = (self.zoom * 1.25).min(8.0); self.zoom_t = std::time::Instant::now(); }
                    ui.label(format!("{:.0}%", self.zoom * 100.0));
                    if ui.button("\u{2212}").clicked() { self.zoom = (self.zoom / 1.25).max(0.1); self.zoom_t = std::time::Instant::now(); }
                    ui.separator();
                    ui.toggle_value(&mut self.show_thumbs, "Pages");
                    if ui.button("Find").clicked() { self.show_find = !self.show_find; }
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
                });
            });
        });
        if self.doc.is_some() || self.tabs.len() > 1 { self.tab_strip(ctx); }
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
        self.perf.mark("top panels");
        self.want_bases.clear();
        if self.show_thumbs && !self.sizes.is_empty() {
            egui::SidePanel::left("thumbs").exact_width(120.0).resizable(false).show(ctx, |ui| {
                egui::ScrollArea::vertical().show_viewport(ui, |ui, vp| {
                    let w = 96.0; let lab = 20.0;
                    let n = self.sizes.len();
                    let hs: Vec<f32> = (0..n).map(|i| w * self.sizes[i].y / self.sizes[i].x.max(1.0) + lab + 6.0).collect();
                    let total: f32 = hs.iter().sum();
                    ui.set_height(total); ui.set_width(110.0);
                    let top = ui.min_rect().top(); let left = ui.min_rect().left() + 8.0;
                    let mut y = 0.0;
                    let mut clicked = None;
                    for i in 0..n {
                        let h = hs[i];
                        if y + h >= vp.top() - 200.0 && y <= vp.bottom() + 200.0 {
                            let r = Rect::from_min_size(pos2(left, top + y), vec2(w, h - lab - 6.0));
                            if y + h >= vp.top() && y <= vp.bottom() {
                                self.want_bases.insert(i);
                                let resp = ui.interact(r, ui.id().with(("th", i)), egui::Sense::click());
                                if let Some(t) = self.view.bases.get_mut(&i) { t.stamp = self.frame; ui.painter().image(t.tex.id(), r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE); }
                                else { ui.painter().rect_filled(r, 0.0, Color32::from_gray(200)); }
                                ui.painter().rect_stroke(r, 0.0, Stroke::new(1.0, Color32::from_gray(120)), StrokeKind::Outside);
                                ui.painter().text(pos2(r.center().x, r.bottom() + 3.0), Align2::CENTER_TOP, format!("{}", i + 1), FontId::proportional(12.0), if i == self.cur_page { Color32::WHITE } else { Color32::from_gray(170) });
                                if resp.clicked() { clicked = Some(i); }
                            }
                        }
                        y += h;
                    }
                    if let Some(i) = clicked { let off = self.offsets(); self.want_scroll_to = Some(off[i] - 12.0); }
                });
            });
        }
        self.perf.mark("thumbs");
        self.dialogs(ctx);
        self.sign_pad(ctx);
        if self.show_ai { self.ai_panel(ctx); }
        egui::CentralPanel::default().frame(egui::Frame::NONE.fill(Color32::from_gray(58))).show(ctx, |ui| {
            let area = ui.available_rect_before_wrap(); self.view_w = area.width();
            // zoom
            // raw zoom: pinch gesture events and ctrl+wheel (a Windows touchpad pinch arrives as ctrl+wheel); egui's own zoom_delta smooths ctrl+wheel
            let (dmx, dmy, dmz) = { dm::set_dpr(ctx.pixels_per_point()); dm::tick(); if dm::active() { ctx.request_repaint(); } dm::take() }; let _ = dmx;
            let (zd0, zn, zdirect) = { let hov = ui.input(|i| i.pointer.hover_pos()).map_or(false, |p| area.contains(p)); let hh = area.height(); let zs = self.diag.z_sens;
                ui.input(|i| { let mut z = 1.0f32; let mut zn = 0.0f32; let mut zw = 0.0f32; let mut zdir = false;
                    for e in &i.events { match e {
                        egui::Event::Zoom(f) => { if hov { z *= *f; } }
                        egui::Event::MouseWheel { unit, delta, modifiers, .. } if hov && (modifiers.command || modifiers.ctrl) => {
                            let pts = match unit { egui::MouseWheelUnit::Line => (delta.x + delta.y) * 40.0, egui::MouseWheelUnit::Page => (delta.x + delta.y) * hh, egui::MouseWheelUnit::Point => delta.x + delta.y };
                            { let px = match unit { egui::MouseWheelUnit::Line => (delta.x + delta.y) * 100.0, egui::MouseWheelUnit::Page => (delta.x + delta.y) * hh, egui::MouseWheelUnit::Point => delta.x + delta.y }; let _ = pts; let frac = matches!(unit, egui::MouseWheelUnit::Line) && { let a = (delta.x + delta.y).abs(); !(a >= 0.99 && (a - a.round()).abs() < 0.01) } || matches!(unit, egui::MouseWheelUnit::Point); if frac { zn += px / 100.0 * zs; zdir = true; } else { zw += (px / 100.0 * zs).clamp(-0.4, 0.4); } }
                        }
                        _ => {} } }
                    if let Some(t) = i.multi_touch() { if hov { z *= t.zoom_delta; } }
                    (z, zn + zw, zdir) }) };
            // Target zoom is driven by the events; the displayed zoom follows it every frame (zoom_step), starting on the first frame.
            if self.ztarget <= 0.0 || (self.zoom / self.zlast - 1.0).abs() > 1e-4 { self.ztarget = self.zoom; }
            let zdirect = zdirect || dmz != 1.0; self.ztarget = (self.ztarget * zd0 * dmz * zn.exp()).clamp(0.1, 8.0);
            let zdt = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);
            let zd = { let nz = if zdirect { self.ztarget } else { zoom_step(self.zoom, self.ztarget, zdt) }; if nz != self.ztarget { ctx.request_repaint(); } nz / self.zoom };
            if zd != 1.0 { self.zoom_t = std::time::Instant::now(); let old = self.zoom; self.zoom = (self.zoom * zd).clamp(0.1, 8.0); if let Some(p) = ui.input(|i| i.pointer.hover_pos()) { let ay = p.y - area.top(); self.scroll = (self.scroll + ay) * (self.zoom / old) - ay; } }
            self.zlast = self.zoom; let settled = true;
            let resp = ui.interact(area, ui.id().with("canvas"), egui::Sense::click_and_drag());
            // touchpad / wheel: read the raw events ourselves (egui's own easing is a ~43 ms low-pass plus coasting)
            let over = resp.hovered() || resp.dragged();
            let mut req = 0.0f32; let mut notch_in = 0.0f32; let mut tp_px = 0.0f32;
            if over { let evs: Vec<egui::Event> = ui.input(|i| i.events.clone()); for e in evs { if let egui::Event::MouseWheel { unit, delta, modifiers, .. } = e {
                if modifiers.command || modifiers.ctrl || modifiers.shift || modifiers.alt { continue; }
                match unit {
                    egui::MouseWheelUnit::Line => { let v = delta.y; let a = v.abs(); if a >= 0.99 && (a - a.round()).abs() < 0.01 { notch_in += v * sys_lines() * (100.0 / 3.0) * self.diag.tp_gain; } else { tp_px += v * sys_lines() * (100.0 / 3.0) * self.diag.tp_gain; } }
                    egui::MouseWheelUnit::Page => req += delta.y * area.height(),
                    egui::MouseWheelUnit::Point => tp_px += delta.y,
                }
            } } }
            let mut rel = 0.0f32;
            { let now = std::time::Instant::now();
              if notch_in != 0.0 { match &mut self.sanim2 { Some(s) if !s.done(now) => s.update_target(now, notch_in, self.diag.tp_tau), _ => { self.sanim2 = Some(ScrollAnim::new(now, notch_in, self.diag.tp_tau)); } } }
              if let Some(s) = &mut self.sanim2 { let v = s.value(now); rel = v - s.applied; s.applied = v; if s.done(now) { self.sanim2 = None; } else { ctx.request_repaint(); } } }
            // touchpad: fine deltas are applied 1:1 (Windows itself supplies the inertia, and stops it on touch). No synthetic momentum.
            let mom = 0.0f32;
            let raw_total = req + notch_in + tp_px;
            let sd = req + rel + tp_px + mom + dmy / ctx.pixels_per_point();
            self.scroll -= sd;
            if self.diag.rec { let t0 = *REC_T0.get_or_init(std::time::Instant::now); let tm = t0.elapsed().as_secs_f32() * 1000.0;
                let mut out = String::new();
                ui.input(|i| { for e in &i.events { match e {
                    egui::Event::MouseWheel { unit, delta, modifiers, .. } => out.push_str(&format!("{:.1} wheel unit={:?} dx={:.4} dy={:.4} ctrl={} shift={} alt={}\n", tm, unit, delta.x, delta.y, modifiers.ctrl, modifiers.shift, modifiers.alt)),
                    egui::Event::Zoom(f) => out.push_str(&format!("{:.1} zoom_event factor={:.5}\n", tm, f)),
                    egui::Event::Touch { phase, pos, force, .. } => out.push_str(&format!("{:.1} touch {:?} {:.0},{:.0} force={:?}\n", tm, phase, pos.x, pos.y, force)),
                    _ => {} } } });
                if !out.is_empty() || sd != 0.0 || zd != 1.0 || self.ztarget != self.zoom { out.push_str(&format!("{:.1} frame dt={:.2}ms sd={:.2} (touchpad {:.2} wheel-anim {:.2} momentum {:.2}) scroll={:.1} zoom={:.4} ztarget={:.4} tvel={:.0}\n", tm, ui.input(|i| i.unstable_dt) * 1000.0, sd, tp_px, rel, mom, self.scroll, self.zoom, self.ztarget, self.tvel)); }
                if !out.is_empty() { use std::io::Write; let p = extras::settings_path().with_file_name("input.log"); if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) { let _ = f.write_all(out.as_bytes()); } } }
            // wheel-to-applied statistics for the log
            if raw_total != 0.0 || self.swipe.is_some() {
                let now = std::time::Instant::now();
                let sw = self.swipe.get_or_insert_with(|| Swipe { t0: now, last: now, req: 0.0, applied: 0.0, series: vec![] });
                if raw_total != 0.0 { sw.last = now; sw.req += raw_total; }
                sw.applied += sd; sw.series.push((now.duration_since(sw.t0).as_secs_f32() * 1000.0, sw.applied));
                if now.duration_since(sw.last).as_millis() > 250 {
                    let sw = self.swipe.take().unwrap();
                    if sw.req.abs() > 30.0 { let t_at = |f: f32| sw.series.iter().find(|(_, a)| a.abs() >= sw.req.abs() * f).map(|x| x.0).unwrap_or(f32::NAN);
                        let first = sw.series.first().map(|x| x.0).unwrap_or(0.0);
                        self.perf.note(format!("wheel swipe: requested {:.0} pt, first movement after {:.0} ms, 90% applied after {:.0} ms, 99% after {:.0} ms ({} mode)", sw.req, first, t_at(0.9), t_at(0.99), "raw")); }
                } else { ctx.request_repaint_after(std::time::Duration::from_millis(60)); }
            }
            if sd != 0.0 || zd != 1.0 { self.perf.active = true; }
            self.scroll_vel = if sd != 0.0 { -sd } else { self.scroll_vel * 0.9 };
            if let Some(t) = self.want_scroll_to.take() { self.scroll = t; }
            let gap = 12.0;
            let total: f32 = self.sizes.iter().map(|s| s.y * self.zoom + gap).sum();
            self.scroll = self.scroll.clamp(0.0, (total - area.height()).max(0.0));
            let mut rects = vec![]; let mut y = area.top() + gap - self.scroll;
            for s in &self.sizes { let sz = *s * self.zoom; rects.push(Rect::from_min_size(pos2(area.center().x - sz.x / 2.0, y), sz)); y += sz.y + gap; }
            let z = self.zoom;
            if let Some(i) = rects.iter().position(|r| r.bottom() > area.center().y) { self.cur_page = i; }
            let to_pdf = |rects: &Vec<Rect>, p: Pos2| -> Option<(usize, Pos2)> {
                let mut best = None; let mut bd = f32::MAX;
                for (i, r) in rects.iter().enumerate() { let d = if p.y < r.top() { r.top() - p.y } else if p.y > r.bottom() { p.y - r.bottom() } else { 0.0 }; if d < bd { bd = d; best = Some(i); } }
                best.map(|i| (i, pos2((p.x - rects[i].left()) / z, (p.y - rects[i].top()) / z)))
            };
            let over_text = if matches!(self.tool, Tool::Select | Tool::Highlight | Tool::Underline | Tool::Strike) {
                match ui.input(|i| i.pointer.hover_pos()).filter(|p| area.contains(*p) && resp.hovered()).and_then(|p| to_pdf(&rects, p).filter(|(pg, _)| rects[*pg].contains(p)).map(|(pg, pp)| (pg, pp))) {
                    Some((pg, pp)) => self.text.get(&pg).map_or(false, |ch| ch.iter().any(|c| c.c != '\n' && c.r.expand(0.5).contains(pp))),
                    None => false }
            } else { false };
            let over_link = if self.tool == Tool::Select {
                match ui.input(|i| i.pointer.hover_pos()).filter(|p| area.contains(*p) && resp.hovered()).and_then(|p| to_pdf(&rects, p).filter(|(pg, _)| rects[*pg].contains(p))) {
                    Some((pg, pp)) => self.links.get(&pg).map_or(false, |ls| ls.iter().any(|(r, _)| pp.x >= r.x0 && pp.x <= r.x1 && pp.y >= r.y0 && pp.y <= r.y1)),
                    None => false }
            } else { false };
            if over_link { ctx.set_cursor_icon(egui::CursorIcon::PointingHand); }
            else if over_text || self.tool == Tool::Text { ctx.set_cursor_icon(egui::CursorIcon::Text); }
            else if matches!(self.tool, Tool::Ink | Tool::Redact | Tool::Sign) { ctx.set_cursor_icon(egui::CursorIcon::Crosshair); }
            else if self.tool == Tool::Eraser { ctx.set_cursor_icon(egui::CursorIcon::PointingHand); }
            let pos = resp.interact_pointer_pos();
            let tool = self.tool;
            match tool {
                Tool::Select | Tool::Highlight | Tool::Underline | Tool::Strike => {
                    if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) {
                        let mut hit_form = false;
                        if resp.clicked() && tool == Tool::Select {
                            let hit = self.page_links(pg).iter().find(|(r, _)| pp.x >= r.x0 && pp.x <= r.x1 && pp.y >= r.y0 && pp.y <= r.y1).map(|x| x.1.clone());
                            match hit {
                                Some(LinkT::Page(p, y)) => { let p = p.min(self.sizes.len().saturating_sub(1)); let off = self.offsets(); self.want_scroll_to = Some(off[p] + y.unwrap_or(0.0) * self.zoom - 12.0); self.cur_page = p; self.sel = None; hit_form = true; }
                                Some(LinkT::Uri(u)) => { extras::open_url(&u); self.status = format!("Opening {u}"); hit_form = true; }
                                None => {}
                            }
                        }
                        if resp.clicked() && tool == Tool::Select && !hit_form { if let Some(d) = self.doc.as_ref() {
                            let fl = ops::fields(d, pg as i32);
                            if let Some(f) = fl.into_iter().find(|f| !f.readonly && pp.x >= f.rect.x0 && pp.x <= f.rect.x1 && pp.y >= f.rect.y0 && pp.y <= f.rect.y1) {
                                use mupdf::pdf::WidgetType as W;
                                match f.kind {
                                    W::Text | W::Combobox => { self.form_edit = Some((pg, f.clone(), f.value.clone())); hit_form = true; }
                                    W::Checkbox | W::RadioButton => { let r = ops::toggle_field(self.doc.as_mut().unwrap(), pg as i32, &f); if r.unwrap_or(false) { self.invalidate(pg); } hit_form = true; }
                                    _ => {}
                                }
                            } } }
                        if hit_form {}
                        else if resp.triple_clicked() { if let Some(k) = self.hit(pg, pp) { let (a, b) = self.line_range(pg, k); self.sel = Some(Sel { page: pg, a, b }); } }
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
                    if resp.clicked() && self.edit.is_none() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) {
                        let ex = self.doc.as_ref().and_then(|d| ops::freetext_at(d, pg as i32, Point::new(pp.x, pp.y)));
                        self.edit = Some(match ex { Some(f) => TextEditState { page: pg, at: pos2(f.rect.x0, f.rect.y0), text: f.text, fresh: true, idx: Some(f.idx), font: f.font, size: f.size, color: f.color, w: f.rect.x1 - f.rect.x0 },
                            None => TextEditState { page: pg, at: pp, text: String::new(), fresh: true, idx: None, font: self.font, size: self.fsize, color: self.color, w: 60.0 } });
                    } } }
                    else if resp.clicked() && self.edit.is_some() { self.commit_text(); }
                }
                Tool::Sign => {
                    if resp.drag_started() { if let Some(pos) = pos { if let Some((pg, pp)) = to_pdf(&rects, pos) { self.sign_start = Some((pg, pp)); } } }
                    if resp.dragged() { if let (Some(pos), Some((pg, _))) = (pos, self.sign_start) { let r = rects[pg]; self.sign_drag = Some(pos2((pos.x - r.left()) / z, (pos.y - r.top()) / z)); } }
                    if resp.drag_stopped() { if let (Some((pg, a)), Some(b)) = (self.sign_start.take(), self.sign_drag.take()) {
                        let r = mupdf::Rect::new(a.x.min(b.x), a.y.min(b.y), a.x.max(b.x), a.y.max(b.y));
                        if (r.x1 - r.x0) > 20.0 && (r.y1 - r.y0) > 10.0 { self.sign_box = Some((pg, r)); self.sign_strokes.clear(); self.sign_cur.clear(); }
                    } }
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
            let typing = ctx.wants_keyboard_input();
            let copy = !typing && ui.input(|i| i.events.iter().any(|e| matches!(e, egui::Event::Copy)) || (i.modifiers.command && i.key_pressed(egui::Key::C)));
            if copy { let t = self.selected_text(); if !t.is_empty() { ctx.copy_text(t.clone()); self.copied = t; self.status = "Copied".into(); } }
            if !typing && ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::A)) { let hp = ui.input(|i| i.pointer.hover_pos()).filter(|p| area.contains(*p)).unwrap_or(area.center()); if let Some((pg, _)) = to_pdf(&rects, hp) { let n = self.page_chars(pg).len(); if n > 0 { self.sel = Some(Sel { page: pg, a: 0, b: n - 1 }); } } }
            // paint
            let painter = ui.painter_at(area);
            for i in 0..self.sizes.len() {
                let r = rects[i];
                if !(r.bottom() >= area.top() && r.top() <= area.bottom()) { continue; }
                painter.rect_filled(r.translate(Vec2::splat(2.0)), 0.0, Color32::from_black_alpha(80));
                self.paint_page(ctx, &painter, i, r, ppp, settled, area);
                if let Some(s) = self.sel { if s.page == i { self.page_chars(i); let ch = &self.text[&i]; for c in &ch[s.a..=s.b.min(ch.len() - 1)] { if c.c == '\n' { continue; } painter.rect_filled(Rect::from_min_max(r.min + c.r.min.to_vec2() * z, r.min + c.r.max.to_vec2() * z), 0.0, Color32::from_rgba_unmultiplied(40, 110, 255, 90)); } } }
                for (k, (pg, hr)) in self.find_hits.iter().enumerate() { if *pg == i { let col = if k == self.find_cur { Color32::from_rgba_unmultiplied(255, 120, 0, 150) } else { Color32::from_rgba_unmultiplied(255, 220, 0, 110) }; painter.rect_filled(Rect::from_min_max(r.min + hr.min.to_vec2() * z, r.min + hr.max.to_vec2() * z), 0.0, col); } }
                if tool == Tool::Ink && self.ink_page == i && self.ink_cur.len() > 1 {
                    let c = Color32::from_rgb((self.color[0] * 255.0) as u8, (self.color[1] * 255.0) as u8, (self.color[2] * 255.0) as u8);
                    let pts: Vec<Pos2> = self.ink_cur.iter().map(|p| r.min + p.to_vec2() * z).collect();
                    painter.add(egui::Shape::line(pts, Stroke::new(self.ink_width * z, c)));
                }
                if let (Some((pg, a)), Some(b)) = (self.sign_start, self.sign_drag) { if pg == i { painter.rect_stroke(Rect::from_two_pos(r.min + a.to_vec2() * z, r.min + b.to_vec2() * z), 0.0, Stroke::new(1.5, Color32::from_rgb(40, 110, 255)), StrokeKind::Middle); } }
                if let (Some((pg, a)), Some(b)) = (self.redact_start, self.redact_cur) { if pg == i { painter.rect_stroke(Rect::from_two_pos(r.min + a.to_vec2() * z, r.min + b.to_vec2() * z), 0.0, Stroke::new(2.0, Color32::RED), StrokeKind::Middle); } }
            }
            self.perf.mark("paint");
            self.build_requests(&rects, area, ppp, settled);
            self.perf.mark("requests");
            if let Some((pg, f, val)) = &mut self.form_edit {
                let r = rects[*pg];
                let rr = Rect::from_min_max(r.min + vec2(f.rect.x0, f.rect.y0) * z, r.min + vec2(f.rect.x1, f.rect.y1) * z);
                let mut done = false;
                egui::Area::new(egui::Id::new("fform")).fixed_pos(rr.min).order(egui::Order::Foreground).show(ctx, |ui| {
                    let te = egui::TextEdit::singleline(val).desired_width(rr.width()).font(FontId::proportional((rr.height() * 0.65).max(10.0)));
                    let resp = ui.add(te); resp.request_focus();
                    if resp.lost_focus() { done = true; }
                });
                if done { let (pg, f, v) = self.form_edit.take().unwrap(); if v != f.value { if let Some(d) = self.doc.as_mut() { let _ = ops::set_field(d, pg as i32, f.xref, &v); } self.invalidate(pg); } }
            }
            // on-page text box (Enter = done, Shift+Enter = new line)
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
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        let t = self.tmp(&format!("snap{}.pdf", N.fetch_add(1, Ordering::SeqCst)));
        match self.doc.as_ref().map(|d| ops::save(d, &t, false)) { Some(Ok(_)) => Some(t), Some(Err(e)) => { self.status = format!("Snapshot failed: {e}"); None } None => None }
    }
    /// Move a finished temp file to its final path. If that path is the open document, release the file first, replace it, then reopen.
    fn commit_file(&mut self, tmp: &str, out: &str) -> Result<(), String> {
        let same = !self.path.is_empty() && std::path::Path::new(&self.path) == std::path::Path::new(out);
        let keep = (self.scroll, self.zoom);
        if same { self.doc = None; }
        let moved = std::fs::rename(tmp, out).or_else(|_| std::fs::copy(tmp, out).map(|_| ()).and_then(|_| std::fs::remove_file(tmp)));
        if same {
            let src = if moved.is_ok() { out.to_string() } else { tmp.to_string() };
            match PdfDocument::open(&src) { Ok(d) => { self.set_doc_src(d, Some(src.clone())); self.scroll = keep.0; self.zoom = keep.1; self.dirty = moved.is_err(); } Err(e) => return Err(format!("reopen failed: {e}")) }
        }
        moved.map_err(|e| format!("could not write {out}: {e}"))
    }
    fn save_inplace(&mut self, p: &str) {
        let tmp = format!("{p}.litepdf-tmp");
        let r = match self.doc.as_ref() { Some(d) => ops::save(d, &tmp, false).map_err(|e| e.to_string()), None => return };
        if let Err(e) = r { let _ = std::fs::remove_file(&tmp); self.status = format!("Save failed: {e}"); return; }
        self.path = p.to_string();
        match self.commit_file(&tmp, p) { Ok(_) => { self.dirty = false; self.status = format!("Saved {p}"); } Err(e) => self.status = format!("Save failed: {e}") }
    }
    pub fn poll(&mut self) {
        while let Ok(m) = self.rx.try_recv() { match m {
            Msg::Status(s) => { self.status = s; self.busy.clear(); }
            Msg::Note(s) => { self.status = s; }
            Msg::Reload(tab, p, note) => {
                let idx = if self.view.tab == tab { Some(self.active) } else { self.tabs.iter().position(|t| t.as_ref().map_or(false, |t| t.view.tab == tab)) };
                match idx {
                    None => { let _ = std::fs::remove_file(&p); }
                    Some(i) => {
                        if i != self.active { self.switch_to(i); }
                        match PdfDocument::open(&p) { Ok(d) => { let keep = self.scroll; self.set_doc_src(d, Some(p.clone())); self.scroll = keep; self.dirty = true; self.status = note; } Err(e) => self.status = format!("Reload failed: {e}") }
                    }
                }
                self.busy.clear();
            }
            Msg::Ai(r) => { self.ai_busy = false; match r { Ok(t) => self.chat.push((false, t)), Err(e) => self.chat.push((false, format!("Error: {e}"))) } }
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
            if ui.button("OCR (English)...").clicked() { self.f1 = (self.cur_page + 1).to_string(); self.f2 = self.f1.clone(); self.dlg = Dlg::Ocr; ui.close(); }
            if ui.button("Sign with certificate...").clicked() { self.f1.clear(); self.f2.clear(); self.f3 = "Approved".into(); self.dlg = Dlg::Sign; ui.close(); }
        });
        ui.menu_button("Diagnostics", |ui| {
            ui.label("Live switches for lag hunting. Log: perf.log in %APPDATA%\\LitePDF");
            ui.add(egui::Slider::new(&mut self.diag.tp_tau, 0.1..=1.5).text("Scroll smoothing length (1.0 = Chromium)"));
            ui.add(egui::Slider::new(&mut self.diag.tp_gain, 0.2..=3.0).text("Scroll distance (1.0 = Chromium: 100 px per wheel tick)"));
            ui.checkbox(&mut self.diag.overlay, "Show frame-time overlay");
            ui.checkbox(&mut self.diag.sync_mode, "Render visible tiles on the UI thread (build b3 behaviour)");
            ui.checkbox(&mut self.diag.snap, "Snap pages and tiles to whole pixels");
            ui.checkbox(&mut self.diag.upload1, "Limit uploads to ~1 tile per frame while scrolling fast");
            ui.add(egui::Slider::new(&mut self.diag.tp_sens, 0.2..=1.5).text("Touchpad scroll sensitivity (touchpad only)"));
            ui.add(egui::Slider::new(&mut self.diag.z_sens, 0.2..=2.0).text("Pinch zoom sensitivity (1.0 = Chromium exp(delta/100))"));
            ui.checkbox(&mut self.diag.rec, "Record input events to input.log (wheel, pinch, touch + resulting zoom/scroll per frame)");
            let mut gf = self.gl_finish.load(std::sync::atomic::Ordering::Relaxed);
            if ui.checkbox(&mut gf, "Wait for GPU each frame (glFinish)").changed() { self.gl_finish.store(gf, std::sync::atomic::Ordering::Relaxed); }
            ui.label("Vsync is on by default. Launch with --vsync=off to compare.");
        });
        if ui.selectable_label(self.show_ai, "AI").clicked() { self.show_ai = !self.show_ai; }
    }
    #[cfg(windows)]
    pub fn gpu_pref_probe(&mut self) {
        use std::os::windows::process::CommandExt;
        let exe = std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_default();
        let out = std::process::Command::new("reg").args(["query", "HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences", "/v", &exe]).creation_flags(0x0800_0000).output();
        let s = match out { Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).lines().filter(|l| l.contains("GpuPreference")).collect::<Vec<_>>().join(" ").trim().to_string(), _ => "no per-app GPU preference set (Windows default)".into() };
        self.perf.header.push_str(&format!("\nWindows GPU preference for this exe: {s}\nworkers: {}", render::WORKERS));
    }
    fn start_ocr(&mut self, from: usize, to: usize, force: bool) {
        let Some(snap) = self.snapshot() else { return };
        let out = self.tmp("ocr.pdf"); let tabid = self.view.tab; let tx = self.tx.clone(); self.busy = "OCR running...".into(); self.status = format!("OCR starting, pages {}-{}...", from + 1, to + 1);
        let _ = std::thread::Builder::new().stack_size(64 << 20).spawn(move || {
            let r = (|| -> Result<extras::OcrStats, String> {
                let mut d = PdfDocument::open(&snap).map_err(|e| e.to_string())?;
                let tx2 = tx.clone();
                let n = extras::ocr_document(&snap, &mut d, from, to, force, &mut |m| { let _ = tx2.send(Msg::Note(m)); })?;
                if n.words > 0 { extras::ocr_log("saving result"); ops::save_fast(&d, &out).map_err(|e| e.to_string())?; extras::ocr_log("result saved, reloading"); }
                Ok(n) })();
            let _ = tx.send(match r {
                Ok(n) if n.words == 0 && n.skipped > 0 && n.done == 0 && n.empty == 0 => Msg::Status(format!("Nothing to do: all {} selected page(s) already have text. Tick \"Re-OCR pages that already have text\" to force.", n.skipped)),
                Ok(n) if n.words == 0 => Msg::Status("OCR found no words on the selected pages (details in ocr.log next to settings.json in %APPDATA%\\LitePDF)".into()),
                Ok(n) => Msg::Reload(tabid, out, format!("OCR done: {} words on {} page(s){}{}. Engine: {}. Unsaved - use Save as.", n.words, n.done, if n.skipped > 0 { format!(", {} already had text (skipped)", n.skipped) } else { String::new() }, if n.empty > 0 { format!(", {} had no readable text", n.empty) } else { String::new() }, n.engine).replace(". Engine", &format!("{}. Engine", if n.failed > 0 { format!(", {} page(s) failed (see ocr.log)", n.failed) } else { String::new() }))),
                Err(e) => Msg::Status(format!("OCR failed: {e}")) });
        });
    }
    fn dialogs(&mut self, ctx: &egui::Context) {
        if self.dlg == Dlg::None { return; }
        let mut close = false;
        let title = match self.dlg { Dlg::Split => "Split", Dlg::Compress => "Compress", Dlg::Protect => "Password and permissions", Dlg::Sign => "Sign with certificate", Dlg::Password => "Password required", Dlg::Merge => "Merge", Dlg::Ocr => "OCR (English)", Dlg::CloseTab(_) => "Unsaved changes", Dlg::None => "" };
        egui::Window::new(title).collapsible(false).resizable(false).anchor(Align2::CENTER_CENTER, vec2(0.0, 0.0)).show(ctx, |ui| {
            match self.dlg {
                Dlg::Password => {
                    ui.label("This PDF is protected. Enter the password:");
                    let r = ui.add(egui::TextEdit::singleline(&mut self.f1).password(true));
                    if ui.button("Open").clicked() || (r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter))) {
                        if let Some(mut d) = self.pending.take() { if d.authenticate(&self.f1).unwrap_or(false) { self.doc_pw = Some(self.f1.clone()); self.set_doc(d); self.path = self.pending_path.clone(); self.dirty = false; self.status = "Opened".into(); close = true; } else { self.status = "Wrong password".into(); self.pending = Some(d); } }
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
                    ui.label("Image resolution (scans are shrunk to about this many dots per inch on an A4 page):");
                    ui.horizontal(|ui| { for d in [100.0f32, 150.0, 200.0, 300.0] { ui.selectable_value(&mut self.comp_dpi, d, format!("{d:.0} dpi")); } });
                    ui.label("Images that would not get smaller are left untouched. If the result is not smaller the original is kept.");
                    if ui.button("Compress and save as...").clicked() {
                        if let Some(out) = pick_save("compressed.pdf") { if let Some(snap) = self.snapshot() {
                            let tmpo = format!("{out}.litepdf-tmp");
                            match ops::compress(&snap, &tmpo, (self.comp_dpi * 11.7) as u32, self.quality as u8) { Ok((a, b)) => { let (s0, s1) = (std::fs::metadata(&snap).map(|m| m.len()).unwrap_or(0), std::fs::metadata(&tmpo).map(|m| m.len()).unwrap_or(0));
                                if s1 >= s0 { let _ = std::fs::remove_file(&tmpo); self.status = format!("No size gain ({a} of {b} images changed, {} KB before, {} KB after). Nothing saved.", s0 / 1024, s1 / 1024); } else {
                                match self.commit_file(&tmpo, &out) { Ok(_) => self.status = format!("Compressed {a}/{b} images: {} KB to {} KB, saved {out}", s0 / 1024, s1 / 1024), Err(e) => self.status = format!("Compress failed: {e}") } } } Err(e) => { let _ = std::fs::remove_file(&tmpo); self.status = format!("Compress failed: {e}") } }
                            let _ = std::fs::remove_file(&snap); } }
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
                            let tmpo = format!("{out}.litepdf-tmp");
                            match ops::encrypt(&snap, &tmpo, &self.f1, &owner, p) { Ok(_) => match self.commit_file(&tmpo, &out) { Ok(_) => self.status = format!("Encrypted (AES-256) and saved {out}"), Err(e) => self.status = format!("Encrypt failed: {e}") }, Err(e) => { let _ = std::fs::remove_file(&tmpo); self.status = format!("Encrypt failed: {e}") } }
                            let _ = std::fs::remove_file(&snap); } }
                        close = true;
                    }
                }
                Dlg::Sign => {
                    ui.horizontal(|ui| { ui.label("Certificate (.p12/.pfx):"); ui.text_edit_singleline(&mut self.f1); if ui.button("Browse").clicked() { if let Some(p) = pick_p12() { self.f1 = p; } } });
                    ui.horizontal(|ui| { ui.label("Certificate password:"); ui.add(egui::TextEdit::singleline(&mut self.f2).password(true)); });
                    ui.horizontal(|ui| { ui.label("Reason:"); ui.text_edit_singleline(&mut self.f3); });
                    if ui.button("Sign and save as...").clicked() {
                        if let Some(out) = pick_save("signed.pdf") { if let Some(snap) = self.snapshot() {
                            let tmpo = format!("{out}.litepdf-tmp");
                            match extras::sign_pdf(&snap, &self.f1, &self.f2, &tmpo, &self.f3) { Ok(_) => match self.commit_file(&tmpo, &out) { Ok(_) => self.status = format!("Signed and saved {out}"), Err(e) => self.status = e }, Err(e) => { let _ = std::fs::remove_file(&tmpo); self.status = e } }
                            let _ = std::fs::remove_file(&snap); } }
                        self.f2.clear(); close = true;
                    }
                }
                Dlg::Ocr => {
                    let n = self.sizes.len();
                    ui.label("Pages to OCR (adds a searchable, selectable text layer; page look and size stay the same):");
                    ui.horizontal(|ui| { ui.label("From"); ui.add(egui::TextEdit::singleline(&mut self.f1).desired_width(50.0)); ui.label("to"); ui.add(egui::TextEdit::singleline(&mut self.f2).desired_width(50.0)); ui.label(format!("of {n}")); });
                    ui.horizontal(|ui| {
                        if ui.button("Current page").clicked() { self.f1 = (self.cur_page + 1).to_string(); self.f2 = self.f1.clone(); }
                        if ui.button("All pages").clicked() { self.f1 = "1".into(); self.f2 = n.to_string(); }
                    });
                    ui.checkbox(&mut self.ocr_force, "Re-OCR pages that already have text");
                    if ui.button("Run OCR").clicked() {
                        let a: usize = self.f1.trim().parse().unwrap_or(0); let b: usize = self.f2.trim().parse().unwrap_or(0);
                        if a >= 1 && b >= a && b <= n { self.start_ocr(a - 1, b - 1, self.ocr_force); close = true; } else { self.status = format!("Enter a range between 1 and {n}"); }
                    }
                }
                Dlg::CloseTab(i) => {
                    ui.label("This document has unsaved changes.");
                    ui.horizontal(|ui| {
                        if ui.button("Save and close").clicked() { self.save_cmd(); if !self.dirty { self.close_tab(i); } close = true; }
                        if ui.button("Discard").clicked() { self.close_tab(i); close = true; }
                        if ui.button("Cancel").clicked() { close = true; }
                    });
                }
                Dlg::None => {}
            }
            if ui.button("Cancel").clicked() { close = true; }
        });
        if close { self.dlg = Dlg::None; }
    }
    fn sign_pad(&mut self, ctx: &egui::Context) {
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
                ui.horizontal(|ui| { ui.label("Provider"); let mut sel = self.settings.provider.clone();
                    egui::ComboBox::from_id_salt("prov").selected_text(sel.clone()).show_ui(ui, |ui| { ui.selectable_value(&mut sel, "Gemini".into(), "Gemini"); ui.selectable_value(&mut sel, "OpenRouter".into(), "OpenRouter"); });
                    if sel != self.settings.provider { extras::save_settings(&self.settings); self.settings.switch_to(&sel); extras::save_settings(&self.settings); } });
                ui.horizontal(|ui| { ui.label("API key"); ui.add(egui::TextEdit::singleline(&mut self.settings.key).password(true).desired_width(200.0)); });
                ui.horizontal(|ui| { ui.label("Model"); ui.add(egui::TextEdit::singleline(&mut self.settings.model).hint_text("type any model name").desired_width(200.0)); });
                ui.small("Key is stored in plain text in a settings file in your user profile on this PC. It is not put in PDFs or the repo.");
                ui.label("Pages sent to the AI");
                ui.horizontal(|ui| { for (m, t) in [(0u8, "Current page"), (1, "Page range"), (2, "Full doc")] { if ui.selectable_label(self.ai_mode == m, t).clicked() { self.ai_mode = m; } } });
                if self.ai_mode == 1 { ui.horizontal(|ui| { ui.label("from"); ui.add(egui::TextEdit::singleline(&mut self.ai_from).desired_width(50.0)); ui.label("to"); ui.add(egui::TextEdit::singleline(&mut self.ai_to).desired_width(50.0).hint_text("last")); }); }
                ui.checkbox(&mut self.ai_use_text, "Send page text"); ui.checkbox(&mut self.ai_use_image, "Send page images (one per page)");
                let pg = self.ai_pages();
                if let (Some(f), Some(l)) = (pg.first(), pg.last()) { ui.label(format!("Sending {} page{} (pages {}-{}){}", pg.len(), if pg.len() == 1 { "" } else { "s" }, f + 1, l + 1, if self.ai_use_image { format!(", text and {} image{}", pg.len(), if pg.len() == 1 { "" } else { "s" }) } else { String::new() })); } else { ui.label("Sending 0 pages"); }
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
    fn ai_pages(&self) -> Vec<usize> {
        ai_page_list(self.ai_mode, &self.ai_from, &self.ai_to, self.cur_page, self.sizes.len())
    }
    fn ask_ai(&mut self) {
        extras::save_settings(&self.settings);
        let c = self.cur_page.min(self.sizes.len().saturating_sub(1));
        let mut text = None; let mut img: Option<String> = None;
        let sel_pages = self.ai_pages();
        if self.ai_use_text {
            let pages: Vec<usize> = sel_pages.clone();
            let mut t = String::new();
            if let Some(d) = &self.doc { for i in pages { if let Ok(pg) = d.load_page(i as i32) { if let Ok(tp) = pg.to_text_page(TextPageFlags::empty()) { if let Ok(s) = tp.to_text() { t.push_str(&format!("--- page {} ---\n{}\n", i + 1, s)); } } } } }
            text = Some(t);
        }
        let mut imgs: Vec<String> = vec![];
        if self.ai_use_image { if let Some(d) = &self.doc { for &pi in &sel_pages { if let Ok(pg) = d.load_page(pi as i32) {
            if let Ok(pm) = pg.to_pixmap(&Matrix::new_scale(1.6, 1.6), &Colorspace::device_rgb(), false, true) {
                let mut jpg = vec![]; let enc = jpeg_encoder::Encoder::new(&mut jpg, 80);
                if enc.encode(pm.samples(), pm.width() as u16, pm.height() as u16, jpeg_encoder::ColorType::Rgb).is_ok() { imgs.push(b64(&jpg)); } } } } } }
        let _ = c; let _ = &mut img;
        let q = std::mem::take(&mut self.chat_input); self.chat.push((true, q.trim().to_string()));
        let (s, h, tx) = (self.settings.clone(), self.chat.clone(), self.tx.clone());
        self.ai_busy = true;
        std::thread::spawn(move || { let r = extras::ai_chat(&s, &h, text.as_deref(), &imgs); let _ = tx.send(Msg::Ai(r)); });
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
        if in_code { code.push_str(line); code.push('\n'); continue; }
        let t = line.trim_start(); let indent = (line.len() - t.len()) as f32 * 3.0;
        if t.is_empty() { ui.add_space(4.0); continue; }
        let (body, size, lead) = if let Some(h) = t.strip_prefix("### ") { (h, 15.0, None) } else if let Some(h) = t.strip_prefix("## ") { (h, 17.0, None) } else if let Some(h) = t.strip_prefix("# ") { (h, 19.0, None) }
            else if let Some(b) = t.strip_prefix("- ").or_else(|| t.strip_prefix("* ")) { (b, 14.0, Some("\u{2022} ".to_string())) }
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

pub fn b64(d: &[u8]) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut o = String::with_capacity(d.len() * 4 / 3 + 4);
    for c in d.chunks(3) { let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        o.push(T[(n >> 18) as usize & 63] as char); o.push(T[(n >> 12) as usize & 63] as char);
        o.push(if c.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' }); o.push(if c.len() > 2 { T[n as usize & 63] as char } else { '=' }); }
    o
}

// ---------------- viewer cache, tabs, perf ----------------
pub struct TileTex { pub tex: TextureHandle, pub bytes: usize, pub rev: u32, pub stamp: u64 }
pub struct DocView {
    pub tab: u32, pub epoch: u32, pub rev: u32, pub rev_all: u32,
    pub tiles: HashMap<usize, HashMap<(u32, u16, u16), TileTex>>,
    pub bases: HashMap<usize, TileTex>,
    pub page_rev: HashMap<usize, u32>,
    pub bytes: usize, pub pw: Option<String>,
    pub refresh_due: Option<std::time::Instant>,
}
impl DocView {
    pub fn new(tab: u32, epoch: u32) -> Self { DocView { tab, epoch, rev: 0, rev_all: 0, tiles: HashMap::new(), bases: HashMap::new(), page_rev: HashMap::new(), bytes: 0, pw: None, refresh_due: None } }
    pub fn required(&self, page: usize) -> u32 { self.page_rev.get(&page).copied().unwrap_or(0).max(self.rev_all) }
    pub fn tile_count(&self) -> usize { self.tiles.values().map(|m| m.len()).sum::<usize>() + self.bases.len() }
    pub fn clear_tex(&mut self) { self.tiles.clear(); self.bases.clear(); self.bytes = 0; }
}
pub struct DocState {
    pub doc: Option<PdfDocument>, pub links: HashMap<usize, Vec<(mupdf::Rect, LinkT)>>, pub sizes: Vec<Vec2>, pub text: HashMap<usize, Vec<Ch>>,
    pub zoom: f32, pub scroll: f32, pub path: String, pub dirty: bool, pub sel: Option<Sel>, pub anchor: Option<(usize, usize)>,
    pub find_q: String, pub find_hits: Vec<(usize, Rect)>, pub find_cur: usize, pub find_for: String, pub cur_page: usize, pub want_scroll_to: Option<f32>, pub view: DocView,
}
impl DocState {
    pub fn empty(tab: u32) -> Self { DocState { doc: None, links: HashMap::new(), sizes: vec![], text: HashMap::new(), zoom: 1.0, scroll: 0.0, path: String::new(), dirty: false, sel: None, anchor: None, find_q: String::new(), find_hits: vec![], find_cur: 0, find_for: String::new(), cur_page: 0, want_scroll_to: None, view: DocView::new(tab, 0) } }
}

#[derive(Clone, Copy)]
pub struct Diag { pub tp_gain: f32, pub tp_tau: f32, pub z_gain: f32, pub z_tau: f32, pub overlay: bool, pub raw_wheel: bool, pub sync_mode: bool, pub snap: bool, pub upload1: bool, pub rec: bool, pub tp_sens: f32, pub z_sens: f32 }
impl Default for Diag { fn default() -> Self { Diag { tp_gain: 1.0, tp_tau: 1.0, z_gain: 1.0, z_tau: 35.0, overlay: false, raw_wheel: true, sync_mode: false, snap: true, upload1: true, rec: false, tp_sens: 0.7, z_sens: 1.0 } } }
pub struct Swipe { pub t0: std::time::Instant, pub last: std::time::Instant, pub req: f32, pub applied: f32, pub series: Vec<(f32, f32)> }

pub struct Perf {
    pub active: bool, any_active: bool, prev_active: bool, last_start: Option<std::time::Instant>, sec: std::time::Instant, t_run: std::time::Instant,
    frames: u32, sum_ms: f32, max_ms: f32, gaps: Vec<f32>, ups: u32, up_sum: f32, up_max: f32, rend: u32, r_sum: f32, r_max: f32, pub sync: u32, pub sync_frame: u32, sync_max: f32, refresh_ms: f32, lines: u32, started: bool,
    marks: Vec<(&'static str, f32)>, t_begin: std::time::Instant, pending: String, pub white: u32, pub baseonly: u32, pub sharp: u32, f_white: bool, f_base: bool, f_any: bool,
    pub last_ms: f32, pub last_gap: f32, pub last_act: std::time::Instant, pub gapn: u32, pub hits: u32, pub misses: u32, pub wlines: u32, pub header: String, slow: u32, pub dropped_up: u32,
}
impl Perf {
    pub fn new() -> Self { let n = std::time::Instant::now(); Perf { active: false, any_active: false, prev_active: false, last_start: None, sec: n, t_run: n, frames: 0, sum_ms: 0.0, max_ms: 0.0, gaps: vec![], ups: 0, up_sum: 0.0, up_max: 0.0, rend: 0, r_sum: 0.0, r_max: 0.0, sync: 0, sync_frame: 0, sync_max: 0.0, refresh_ms: 0.0, lines: 0, started: false,
        marks: vec![], t_begin: n, pending: String::new(), white: 0, baseonly: 0, sharp: 0, f_white: false, f_base: false, f_any: false, last_ms: 0.0, last_gap: 0.0, last_act: n, gapn: 0, hits: 0, misses: 0, wlines: 0, header: String::new(), slow: 0, dropped_up: 0 } }
    pub fn upload(&mut self, ms: f32) { self.ups += 1; self.up_sum += ms; self.up_max = self.up_max.max(ms); }
    pub fn rendered(&mut self, ms: f32) { self.rend += 1; self.r_sum += ms; self.r_max = self.r_max.max(ms); }
    pub fn synced(&mut self, ms: f32) { self.sync += 1; self.sync_frame += 1; self.sync_max = self.sync_max.max(ms); }
    pub fn refreshed(&mut self, ms: f32) { self.refresh_ms = self.refresh_ms.max(ms); }
    pub fn begin(&mut self) { self.t_begin = std::time::Instant::now(); self.marks.clear(); }
    pub fn mark(&mut self, name: &'static str) { let t = self.t_begin.elapsed().as_secs_f32() * 1000.0; self.marks.push((name, t)); }
    pub fn note(&mut self, s: String) { if self.pending.len() < 200_000 { self.pending.push_str(&format!("t={:>4}s  {}\n", self.t_run.elapsed().as_secs(), s)); } }
    pub fn vis(&mut self, state: u8) { self.f_any = true; match state { 0 => self.f_white = true, 1 => self.f_base = true, _ => {} } }
    pub fn worker_job(&mut self, wid: usize, kind: &str, page: usize, total: f32, list: f32, hit: bool) {
        self.rendered(total); if hit { self.hits += 1 } else { self.misses += 1 }
        if total > 150.0 && self.wlines < 400 { self.wlines += 1; self.note(format!("worker{wid} slow job: {kind} page {page} took {total:.0} ms (display list {list:.0} ms, draw {:.0} ms, list cache {})", total - list, if hit { "hit" } else { "miss" })); }
    }
    pub fn frame(&mut self, t0: std::time::Instant, bytes: usize, tiles: usize, queue: usize) {
        self.sync_frame = 0;
        let ms = t0.elapsed().as_secs_f32() * 1000.0; self.last_ms = ms;
        if let Some(l) = self.last_start { let gap = t0.duration_since(l).as_secs_f32() * 1000.0; self.last_gap = gap; if self.prev_active && self.active && gap < 2000.0 { self.gaps.push(gap); if gap > 40.0 && self.gapn < 300 { self.gapn += 1; self.note(format!("GAP {gap:.0} ms between frames while active (previous frame's own cost {:.1} ms)", self.max_ms)); } } }
        self.last_start = Some(t0); self.prev_active = self.active;
        self.frames += 1; self.sum_ms += ms; self.max_ms = self.max_ms.max(ms);
        if self.f_any && self.active { if self.f_white { self.white += 1; } else if self.f_base { self.baseonly += 1; } else { self.sharp += 1; } }
        self.f_white = false; self.f_base = false; self.f_any = false;
        if ms > 30.0 && self.slow < 300 {
            self.slow += 1;
            let mut prev = 0.0; let mut s = String::new();
            for (n, t) in &self.marks { s.push_str(&format!(" {n}={:.1}", t - prev)); prev = *t; }
            s.push_str(&format!(" rest={:.1}", ms - prev));
            self.note(format!("SLOW frame {ms:.1} ms (ms per stage:{s}; sync tile renders this second={})", self.sync));
        }
        if self.active { self.any_active = true; }
        self.active = false;
        if self.sec.elapsed().as_secs_f32() >= 1.0 {
            use std::io::Write;
            let busy = (self.any_active || self.sync > 0 || self.refresh_ms > 0.0) && self.lines < 20000;
            if busy || !self.pending.is_empty() {
                let p = extras::settings_path().with_file_name("perf.log");
                if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
                let f = if !self.started { self.started = true; std::fs::OpenOptions::new().create(true).write(true).truncate(true).open(&p) } else { std::fs::OpenOptions::new().create(true).append(true).open(&p) };
                if let Ok(mut f) = f {
                    if self.lines == 0 { let _ = writeln!(f, "LitePDF perf log (build b13). One line per second while scrolling/zooming. frame = time inside our UI update. gap = time between frame starts (p50/p95/p99/max, nothing filtered). up = texture uploads. render = worker jobs. vis = frames whose visible pages were white / low-res base only / sharp. lc = display-list cache hits/misses.\n{}", self.header); }
                    if busy {
                        let mut g = std::mem::take(&mut self.gaps); g.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                        let q = |f: f32| -> f32 { if g.is_empty() { 0.0 } else { g[((g.len() as f32 - 1.0) * f).round() as usize] } };
                        let _ = writeln!(f, "t={:>4}s frames={:<3} frame_avg={:.1}ms frame_max={:.1}ms gap p50={:.1} p95={:.1} p99={:.1} max={:.1}ms up={}x(max {:.1}ms) render={}x(avg {:.0}ms max {:.0}ms) sync={}x(max {:.0}ms) refresh_max={:.0}ms queue={} tex={} mem={}MB vis(white/base/sharp)={}/{}/{} lc={}/{}",
                            self.t_run.elapsed().as_secs(), self.frames, self.sum_ms / self.frames.max(1) as f32, self.max_ms, q(0.5), q(0.95), q(0.99), g.last().cloned().unwrap_or(0.0), self.ups, self.up_max, self.rend, self.r_sum / self.rend.max(1) as f32, self.r_max, self.sync, self.sync_max, self.refresh_ms, queue, tiles, bytes >> 20, self.white, self.baseonly, self.sharp, self.hits, self.misses);
                        self.lines += 1;
                    }
                    if !self.pending.is_empty() { let _ = f.write_all(std::mem::take(&mut self.pending).as_bytes()); }
                }
            }
            self.gaps.clear();
            self.sec = std::time::Instant::now(); self.frames = 0; self.sum_ms = 0.0; self.max_ms = 0.0; self.ups = 0; self.up_sum = 0.0; self.up_max = 0.0; self.rend = 0; self.r_sum = 0.0; self.r_max = 0.0; self.sync = 0; self.sync_max = 0.0; self.refresh_ms = 0.0; self.any_active = false; self.white = 0; self.baseonly = 0; self.sharp = 0; self.hits = 0; self.misses = 0;
        }
    }
}

const TEX_BUDGET: usize = 512 << 20;
const UPLOAD_BUDGET: usize = 12 << 20;

impl App {
    fn tile_grid(&self, i: usize, r: Rect, ppp: f32) -> (u32, f32, Pos2, Vec<(u16, u16, Rect)>) {
        let sz = self.sizes[i]; let ssc = self.zoom * ppp;
        let sk = render::scale_key(ssc); let s = render::key_scale(sk); let f = ssc / s;
        let (pw, ph) = render::page_px((sz.x, sz.y), s);
        let o = if self.diag.snap { pos2((r.min.x * ppp).round() / ppp, (r.min.y * ppp).round() / ppp) } else { r.min };
        let t = render::TILE; let (nx, ny) = ((pw + t - 1) / t, (ph + t - 1) / t);
        let mut v = vec![];
        for ty in 0..ny { for tx in 0..nx {
            let (x0, y0) = (tx * t, ty * t); let (w, h) = ((x0 + t).min(pw) - x0, (y0 + t).min(ph) - y0);
            v.push((tx as u16, ty as u16, Rect::from_min_size(pos2(o.x + x0 as f32 * f / ppp, o.y + y0 as f32 * f / ppp), vec2(w as f32 * f / ppp, h as f32 * f / ppp))));
        } }
        (sk, f, o, v)
    }
    fn tile_missing(&self, i: usize, sk: u32, tx: u16, ty: u16) -> bool {
        match self.view.tiles.get(&i).and_then(|m| m.get(&(sk, tx, ty))) { Some(t) => t.rev < self.view.required(i), None => true }
    }
    #[allow(clippy::too_many_arguments)]
    fn paint_page(&mut self, ctx: &egui::Context, painter: &egui::Painter, i: usize, r: Rect, ppp: f32, _settled: bool, area: Rect) {
        let uv = Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0));
        let rs = if self.diag.snap { Rect::from_min_size(pos2((r.min.x * ppp).round() / ppp, (r.min.y * ppp).round() / ppp), r.size()) } else { r };
        let has_base = self.view.bases.contains_key(&i);
        if let Some(b) = self.view.bases.get_mut(&i) { b.stamp = self.frame; painter.image(b.tex.id(), rs, uv, Color32::WHITE); } else { painter.rect_filled(r, 0.0, Color32::WHITE); }
        if self.doc.is_none() { return; }
        let (sk, f, o, grid) = self.tile_grid(i, r, ppp);
        let ssc = self.zoom * ppp;
        let required = self.view.required(i);
        let awaiting = required > self.view.rev;
        let vis: Vec<(u16, u16, Rect)> = grid.into_iter().filter(|(_, _, tr)| tr.intersects(area)).collect();
        // edits not yet in the worker's copy: render the visible tiles right here so the change shows at once
        if self.perf.sync_frame < 1 {
            for (tx, ty, _) in &vis {
                let stale = self.view.tiles.get(&i).and_then(|m| m.get(&(sk, *tx, *ty))).map_or(false, |t| t.rev < required);
                if self.tile_missing(i, sk, *tx, *ty) && (awaiting || stale || self.diag.sync_mode) {
                    let t0 = std::time::Instant::now();
                    let done = (|| -> Option<(usize, usize, Vec<u8>)> {
                        let doc = self.doc.as_ref()?; let pg = doc.load_page(i as i32).ok()?; let b = pg.bounds().ok()?;
                        let l = pg.to_display_list(true).ok()?;
                        render::render_job_doc(&l, (b.x1 - b.x0, b.y1 - b.y0), Kind::Tile { key: sk, tx: *tx, ty: *ty })
                    })();
                    if let Some((w, h, rgba)) = done { self.put_tile(ctx, i, Some((sk, *tx, *ty)), w, h, &rgba, required); }
                    self.perf.synced(t0.elapsed().as_secs_f32() * 1000.0);
                }
            }
        }
        let n_missing = vis.iter().filter(|(tx, ty, _)| self.tile_missing(i, sk, *tx, *ty)).count();
        let have_all = n_missing == 0;
        if !have_all { self.miss_frame += n_missing; }
        let tr_of = |key: u32, tx: u16, ty: u16, w: usize, h: usize| -> Rect {
            let fk = ssc / render::key_scale(key);
            Rect::from_min_size(pos2(o.x + (tx as i32 * render::TILE) as f32 * fk / ppp, o.y + (ty as i32 * render::TILE) as f32 * fk / ppp), vec2(w as f32 * fk / ppp, h as f32 * fk / ppp))
        };
        let frame = self.frame;
        if let Some(m) = self.view.tiles.get_mut(&i) {
            if !have_all {
                let mut best: Option<u32> = None;
                for k in m.keys().map(|k| k.0).filter(|k| *k != sk) { let d = (k as f32 / sk as f32).ln().abs(); if best.map_or(true, |b| d < (b as f32 / sk as f32).ln().abs()) { best = Some(k); } }
                if let Some(bk) = best { for (k, t) in m.iter_mut() { if k.0 == bk { let sz = t.tex.size(); let rr = tr_of(bk, k.1, k.2, sz[0], sz[1]); if rr.intersects(area) { t.stamp = frame; painter.image(t.tex.id(), rr, uv, Color32::WHITE); } } } }
            }
            for (tx, ty, _) in &vis { if let Some(t) = m.get_mut(&(sk, *tx, *ty)) { t.stamp = frame; let sz = t.tex.size(); painter.image(t.tex.id(), tr_of(sk, *tx, *ty, sz[0], sz[1]), uv, Color32::WHITE); } }
        }
        let _ = f;
        if r.intersects(area) { let sharp = self.view.tiles.get(&i).map_or(false, |m| vis.iter().all(|(tx, ty, _)| m.contains_key(&(sk, *tx, *ty)))); self.perf.vis(if sharp { 2 } else if has_base { 1 } else { 0 }); }
    }
    fn put_tile(&mut self, ctx: &egui::Context, page: usize, tile: Option<(u32, u16, u16)>, w: usize, h: usize, rgba: &[u8], rev: u32) {
        let img = ColorImage::from_rgba_unmultiplied([w, h], rgba);
        let name = match tile { Some((k, x, y)) => format!("t{page}-{k}-{x}-{y}"), None => format!("b{page}") };
        let tex = ctx.load_texture(name, img, egui::TextureOptions::LINEAR);
        let bytes = w * h * 4;
        let tt = TileTex { tex, bytes, rev, stamp: self.frame };
        let old = match tile { Some((k, x, y)) => self.view.tiles.entry(page).or_default().insert((k, x, y), tt), None => self.view.bases.insert(page, tt) };
        if let Some(o) = old { self.view.bytes = self.view.bytes.saturating_sub(o.bytes); }
        self.view.bytes += bytes;
    }
    fn evict(&mut self) {
        while self.view.bytes > TEX_BUDGET {
            let mut best: Option<(u64, usize, Option<(u32, u16, u16)>)> = None;
            for (p, m) in &self.view.tiles { for (k, t) in m { if t.stamp < self.frame && best.map_or(true, |b| t.stamp < b.0) { best = Some((t.stamp, *p, Some(*k))); } } }
            for (p, t) in &self.view.bases { if t.stamp < self.frame && best.map_or(true, |b| t.stamp < b.0) { best = Some((t.stamp, *p, None)); } }
            let Some((_, p, k)) = best else { break };
            let removed = match k { Some(k) => self.view.tiles.get_mut(&p).and_then(|m| m.remove(&k)), None => self.view.bases.remove(&p) };
            if let Some(t) = removed { self.view.bytes = self.view.bytes.saturating_sub(t.bytes); } else { break; }
        }
        self.view.tiles.retain(|_, m| !m.is_empty());
    }
    fn poll_render(&mut self, ctx: &egui::Context) {
        let ppp = ctx.pixels_per_point();
        let cur_key = render::scale_key(self.zoom * ppp);
        let fast = self.diag.upload1 && self.scroll_vel.abs() > 25.0;
        let upl_t = std::time::Instant::now(); let mut upl_n = 0u32;
        let mut budget = if fast { 4_200_000usize } else { UPLOAD_BUDGET }; let mut more = false;
        loop {
            let Some(w) = self.worker.as_ref() else { break };
            if budget == 0 || (upl_n > 0 && upl_t.elapsed().as_secs_f32() > 0.004) { more = true; break; }
            let Ok(res) = w.rx.try_recv() else { break };
            match res {
                Res::Sizes { tab, epoch, sizes } => {
                    let v: Vec<Vec2> = sizes.into_iter().map(|(x, y)| vec2(x, y)).collect();
                    if tab == self.view.tab && epoch == self.view.epoch {
                        let n = self.sizes.len(); let p = self.cur_page.min(n.saturating_sub(1));
                        let off = self.offsets();
                        let frac = if n > 0 { (self.scroll - (off[p] - 12.0)) / (self.sizes[p].y * self.zoom + 12.0) } else { 0.0 };
                        self.sizes = v;
                        if p < self.sizes.len() { let off2 = self.offsets(); self.scroll = off2[p] - 12.0 + frac * (self.sizes[p].y * self.zoom + 12.0); }
                    } else if let Some(st) = self.tabs.iter_mut().flatten().find(|t| t.view.tab == tab && t.view.epoch == epoch) { st.sizes = v; }
                    ctx.request_repaint();
                }
                Res::JobFailed { job, why } => { self.perf.note(format!("worker job failed: page {} {:?}: {why}", job.page + 1, job.kind)); self.last_sent.clear(); }
                Res::Failed { tab, epoch, msg } => { if tab == self.view.tab && epoch == self.view.epoch { self.status = format!("Render failed: {msg}"); } }
                Res::Text { job, rev, chars, links, ms } => {
                    self.perf.rendered(ms);
                    if job.tab != self.view.tab || job.epoch != self.view.epoch || rev < self.view.required(job.page) { self.last_sent.clear(); continue; }
                    if !self.text.contains_key(&job.page) {
                        let v: Vec<Ch> = chars.into_iter().map(|(c, q, line)| Ch { c, r: Rect::from_min_max(pos2(q[0], q[1]), pos2(q[2], q[3])), line }).collect();
                        self.text.insert(job.page, v);
                    }
                    if !self.links.contains_key(&job.page) {
                        let v: Vec<(mupdf::Rect, LinkT)> = links.into_iter().map(|(r, l)| (mupdf::Rect { x0: r[0], y0: r[1], x1: r[2], y1: r[3] }, match l { render::RawLink::Page(p, y) => LinkT::Page(p, y), render::RawLink::Uri(u) => LinkT::Uri(u) })).collect();
                        self.links.insert(job.page, v);
                    }
                }
                Res::Img { job, rev, w, h, rgba, ms, list_ms, hit, wid } => {
                    self.last_res = std::time::Instant::now();
                    self.perf.worker_job(wid, match job.kind { Kind::Base => "base", _ => "tile" }, job.page, ms, list_ms, hit);
                    if job.tab != self.view.tab || job.epoch != self.view.epoch { continue; }
                    if rev < self.view.required(job.page) { self.last_sent.clear(); continue; }
                    let tile = match job.kind { Kind::Tile { key, tx, ty } => { if key != cur_key { continue; } Some((key, tx, ty)) } _ => None };
                    let t0 = std::time::Instant::now();
                    self.put_tile(ctx, job.page, tile, w, h, &rgba, rev);
                    upl_n += 1;
                    budget = budget.saturating_sub(if tile.is_none() && fast { w * h * 2 } else { w * h * 4 });
                    self.perf.upload(t0.elapsed().as_secs_f32() * 1000.0);
                }
            }
        }
        if more { ctx.request_repaint(); }
        self.evict();
    }
    /// After an edit the worker's copy of the document is refreshed once input has been idle for a moment.
    fn refresh_worker(&mut self, ctx: &egui::Context) {
        let Some(due) = self.view.refresh_due else { return };
        if self.doc.is_none() { self.view.refresh_due = None; return; }
        if std::time::Instant::now() < due || ctx.input(|i| i.pointer.any_down()) { ctx.request_repaint(); return; }
        self.view.refresh_due = None;
        let t0 = std::time::Instant::now();
        let mut buf: Vec<u8> = vec![];
        if let Some(d) = &self.doc { if d.write_to(&mut buf).is_err() { return; } }
        self.view.rev += 1;
        let (tab, epoch, rev, pw) = (self.view.tab, self.view.epoch, self.view.rev, self.view.pw.clone());
        self.last_sent.clear();
        self.worker().send(Cmd::Open { tab, epoch, rev, src: Src::Bytes(std::sync::Arc::new(buf)), pw, want_sizes: false });
        self.perf.refreshed(t0.elapsed().as_secs_f32() * 1000.0);
        ctx.request_repaint();
    }
    fn build_requests(&mut self, rects: &[Rect], area: Rect, ppp: f32, settled: bool) {
        let n = self.sizes.len();
        if self.doc.is_none() || n == 0 || rects.len() != n { return; }
        let h = area.height(); let down = self.scroll_vel >= 0.0;
        let pf = Rect::from_min_max(pos2(area.left(), area.top() - if down { 0.5 } else { 1.0 } * h), pos2(area.right(), area.bottom() + if down { 1.0 } else { 0.5 } * h));
        let wide = Rect::from_min_max(pos2(area.left(), area.top() - 2.5 * h), pos2(area.right(), area.bottom() + 2.5 * h));
        let (tab, epoch) = (self.view.tab, self.view.epoch); let cy = area.center().y;
        let mut v: Vec<(u8, f32, Job)> = vec![];
        let base_missing = |this: &App, i: usize| -> bool { match this.view.bases.get(&i) { Some(b) => b.rev < this.view.required(i), None => true } };
        for i in 0..n {
            let r = rects[i];
            if r.bottom() < wide.top() { continue; } if r.top() > wide.bottom() { break; }
            if self.view.required(i) > self.view.rev { continue; }
            let dist = (r.center().y - cy).abs(); let vis = r.intersects(area);
            if base_missing(self, i) { v.push((if vis { 0 } else if r.intersects(pf) { 2 } else { 4 }, dist, Job { tab, epoch, page: i, kind: Kind::Base })); }
            if settled && r.intersects(pf) {
                let (sk, _, _, grid) = self.tile_grid(i, r, ppp);
                for (tx, ty, tr) in grid { if tr.intersects(pf) && self.tile_missing(i, sk, tx, ty) { v.push((if tr.intersects(area) { 1 } else { 3 }, (tr.center().y - cy).abs(), Job { tab, epoch, page: i, kind: Kind::Tile { key: sk, tx, ty } })); } }
            }
        }
        // text + links for the pages being looked at, extracted on the workers (never on the UI thread)
        if self.view.rev >= self.view.rev_all {
            let cp = self.cur_page;
            for i in [cp, cp + 1, cp.saturating_sub(1)] { if i < n && !(self.text.contains_key(&i) && self.links.contains_key(&i)) && self.view.required(i) <= self.view.rev { v.push((5, (rects[i].center().y - cy).abs(), Job { tab, epoch, page: i, kind: Kind::Text })); } }
        }
        for &i in &self.want_bases { if i < n && self.view.required(i) <= self.view.rev && base_missing(self, i) { v.push((1, 0.0, Job { tab, epoch, page: i, kind: Kind::Base })); } }
        v.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal)));
        v.truncate(90);
        let jobs: Vec<Job> = v.into_iter().map(|x| x.2).collect();
        let set: HashSet<Job> = jobs.iter().copied().collect();
        if set != self.last_sent { self.last_sent = set; self.worker().send(Cmd::Want(jobs)); }
    }

    // ----- tabs -----
    fn take_state(&mut self) -> DocState {
        DocState { doc: self.doc.take(), links: std::mem::take(&mut self.links), sizes: std::mem::take(&mut self.sizes), text: std::mem::take(&mut self.text), zoom: self.zoom, scroll: self.scroll, path: std::mem::take(&mut self.path), dirty: self.dirty, sel: self.sel.take(), anchor: self.anchor.take(),
            find_q: std::mem::take(&mut self.find_q), find_hits: std::mem::take(&mut self.find_hits), find_cur: self.find_cur, find_for: std::mem::take(&mut self.find_for), cur_page: self.cur_page, want_scroll_to: self.want_scroll_to.take(), view: std::mem::replace(&mut self.view, DocView::new(0, 0)) }
    }
    fn put_state(&mut self, s: DocState) {
        self.doc = s.doc; self.links = s.links; self.sizes = s.sizes; self.text = s.text; self.zoom = s.zoom; self.scroll = s.scroll; self.path = s.path; self.dirty = s.dirty; self.sel = s.sel; self.anchor = s.anchor;
        self.find_q = s.find_q; self.find_hits = s.find_hits; self.find_cur = s.find_cur; self.find_for = s.find_for; self.cur_page = s.cur_page; self.want_scroll_to = s.want_scroll_to; self.view = s.view;
        self.last_sent.clear(); self.form_edit = None; self.edit = None;
    }
    fn find_tab(&self, p: &str) -> Option<usize> {
        let same = |a: &str| !a.is_empty() && std::path::Path::new(a) == std::path::Path::new(p);
        if same(&self.path) { return Some(self.active); }
        self.tabs.iter().position(|t| t.as_ref().map_or(false, |t| same(&t.path)))
    }
    pub fn switch_to(&mut self, i: usize) {
        if i == self.active || i >= self.tabs.len() { return; }
        self.commit_text();
        let mut cur = self.take_state(); cur.view.clear_tex();
        self.tabs[self.active] = Some(cur);
        if let Some(st) = self.tabs[i].take() { self.put_state(st); }
        self.active = i;
        self.perf.active = true;
    }
    fn new_tab_blank(&mut self) {
        self.commit_text();
        let mut cur = self.take_state(); cur.view.clear_tex();
        self.tabs[self.active] = Some(cur);
        self.tabs.push(None); self.active = self.tabs.len() - 1;
        let id = self.next_tab; self.next_tab += 1;
        self.put_state(DocState::empty(id));
        self.zoom = 1.0;
    }
    fn request_close(&mut self, i: usize) {
        if i >= self.tabs.len() { return; }
        let dirty = if i == self.active { self.dirty } else { self.tabs[i].as_ref().map_or(false, |t| t.dirty) };
        if dirty { self.switch_to(i); self.dlg = Dlg::CloseTab(self.active); } else { self.close_tab(i); }
    }
    pub fn close_tab(&mut self, i: usize) {
        if i >= self.tabs.len() { return; }
        let id = if i == self.active { self.view.tab } else { self.tabs[i].as_ref().map_or(0, |t| t.view.tab) };
        self.worker().send(Cmd::Close { tab: id });
        if i == self.active {
            let _ = self.take_state(); self.tabs.remove(i);
            if self.tabs.is_empty() { self.tabs.push(None); self.active = 0; let nid = self.next_tab; self.next_tab += 1; self.put_state(DocState::empty(nid)); }
            else { let n = i.min(self.tabs.len() - 1); self.active = n; if let Some(st) = self.tabs[n].take() { self.put_state(st); } }
            self.sel = None;
        } else { self.tabs.remove(i); if i < self.active { self.active -= 1; } }
        self.last_sent.clear(); self.perf.active = true;
    }
    fn tab_strip(&mut self, ctx: &egui::Context) {
        let mut sw: Option<usize> = None; let mut cl: Option<usize> = None; let mut add = false;
        egui::TopBottomPanel::top("tabs").frame(egui::Frame::NONE.fill(Color32::from_gray(26)).inner_margin(egui::Margin::symmetric(6, 3))).show(ctx, |ui| {
            egui::ScrollArea::horizontal().id_salt("tabscroll").scroll_bar_visibility(egui::scroll_area::ScrollBarVisibility::AlwaysHidden).show(ui, |ui| { ui.horizontal(|ui| {
                for i in 0..self.tabs.len() {
                    let (path, dirty) = if i == self.active { (self.path.clone(), self.dirty) } else { self.tabs[i].as_ref().map_or((String::new(), false), |t| (t.path.clone(), t.dirty)) };
                    let nm = if path.is_empty() { "New tab".to_string() } else { std::path::Path::new(&path).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default() };
                    let short: String = if nm.chars().count() > 22 { format!("{}...", nm.chars().take(20).collect::<String>()) } else { nm.clone() };
                    let r = ui.selectable_label(i == self.active, format!("{}{}", short, if dirty { " *" } else { "" })).on_hover_text(if path.is_empty() { nm } else { path });
                    if r.clicked() { sw = Some(i); }
                    if r.middle_clicked() { cl = Some(i); }
                    if ui.add(egui::Button::new("\u{2715}").frame(false).small()).clicked() { cl = Some(i); }
                    ui.add_space(6.0);
                }
                if ui.add(egui::Button::new("+").frame(false)).on_hover_text("Open in a new tab").clicked() { add = true; }
            }); });
        });
        if let Some(i) = sw { self.switch_to(i); }
        if let Some(i) = cl { self.request_close(i); }
        if add { for p in pick_open(true) { self.open(&p); } }
    }
}

/// Which pages (0-based) the AI gets. mode 0 current page, 1 from-to range (1-based, blank "to" = last page), 2 whole document.
pub fn ai_page_list(mode: u8, from: &str, to: &str, cur: usize, n: usize) -> Vec<usize> {
    if n == 0 { return vec![]; }
    match mode {
        0 => vec![cur.min(n - 1)],
        2 => (0..n).collect(),
        _ => {
            let f = from.trim().parse::<usize>().unwrap_or(1).clamp(1, n);
            let t = if to.trim().is_empty() { n } else { to.trim().parse::<usize>().unwrap_or(n).clamp(1, n) };
            let (f, t) = if f <= t { (f, t) } else { (t, f) };
            (f - 1..t).collect()
        }
    }
}

/// A wheel notch arrives as a whole number of lines; a touchpad sends fractions.
pub fn is_notch(d: f32) -> bool { d.abs() >= 0.99 && (d.abs() - d.abs().round()).abs() < 0.02 }
/// Chromium's ease-in-out timing function, cubic-bezier(0.42, 0, 0.58, 1): progress p (0..1) to eased fraction.
pub fn cubic_ease(p: f32) -> f32 {
    if p <= 0.0 { return 0.0; } if p >= 1.0 { return 1.0; }
    let bx = |t: f32| 3.0 * (1.0 - t) * (1.0 - t) * t * 0.42 + 3.0 * (1.0 - t) * t * t * 0.58 + t * t * t;
    let by = |t: f32| 3.0 * (1.0 - t) * t * t + t * t * t;
    let (mut lo, mut hi) = (0.0f32, 1.0f32);
    for _ in 0..24 { let m = (lo + hi) / 2.0; if bx(m) < p { lo = m; } else { hi = m; } }
    by((lo + hi) / 2.0)
}

/// Port of Chromium's cc::ScrollOffsetAnimationCurve for mouse-wheel scrolls (ease-in-out cubic bezier 0.42,0,0.58,1,
/// kInverseDelta duration 6..12 frames at 60 Hz, UpdateTarget keeps the current velocity). One deliberate change: a brand
/// new animation starts with a non-zero initial slope so it moves on the first frame instead of easing in from rest.
static REC_T0: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
/// Moves the displayed zoom toward the target in log space: exponential approach (tau 20 ms) with a hard cap of 10 ln-units/s,
/// both scaled by the frame time, so the shown zoom passes through every intermediate value on any refresh rate.
/// Lines per wheel tick from Windows (SPI_GETWHEELSCROLLLINES), as Chromium's web_input_event_builders_win.cc reads it; default 3.
pub fn sys_lines() -> f32 {
    #[cfg(windows)]
    { extern "system" { fn SystemParametersInfoW(a: u32, b: u32, c: *mut std::ffi::c_void, d: u32) -> i32; }
      let mut n: u32 = 3; let ok = unsafe { SystemParametersInfoW(0x0068, 0, &mut n as *mut u32 as *mut _, 0) };
      if ok != 0 && n > 0 && n < 100 { return n as f32; } }
    3.0
}
pub fn zoom_step(cur: f32, target: f32, dt: f32) -> f32 {
    let d = (target / cur).ln(); if d.abs() < 1e-4 { return target; }
    let cap = 10.0 * dt; let step = (d * (1.0 - (-dt / 0.02).exp())).clamp(-cap, cap); cur * step.exp()
}
pub struct ScrollAnim { t0: std::time::Instant, init: f32, target: f32, total: f32, last_retarget: f32, slope: f32, pub applied: f32, dscale: f32 }
fn bez_xy(x1: f32, y1: f32, x2: f32, y2: f32, t: f32) -> (f32, f32) {
    let u = 1.0 - t;
    (3.0 * u * u * t * x1 + 3.0 * u * t * t * x2 + t * t * t, 3.0 * u * u * t * y1 + 3.0 * u * t * t * y2 + t * t * t)
}
fn bez_dxy(x1: f32, y1: f32, x2: f32, y2: f32, t: f32) -> (f32, f32) {
    let u = 1.0 - t;
    (3.0 * u * u * x1 + 6.0 * u * t * (x2 - x1) + 3.0 * t * t * (1.0 - x2), 3.0 * u * u * y1 + 6.0 * u * t * (y2 - y1) + 3.0 * t * t * (1.0 - y2))
}
fn bez_solve(x1: f32, x2: f32, p: f32) -> f32 { let (mut lo, mut hi) = (0.0f32, 1.0f32); for _ in 0..30 { let m = (lo + hi) / 2.0; if bez_xy(x1, 0.0, x2, 1.0, m).0 < p { lo = m; } else { hi = m; } } (lo + hi) / 2.0 }
impl ScrollAnim {
    fn seg_duration(&self, delta: f32) -> f32 { (14.0 - delta.abs() / 60.0).clamp(6.0, 12.0) / 60.0 * self.dscale }
    fn ease(&self, p: f32) -> f32 { let (x1, y1) = (0.42, 0.42 * self.slope); let t = bez_solve(x1, 0.58, p); bez_xy(x1, y1, 0.58, 1.0, t).1 }
    fn ease_vel(&self, p: f32) -> f32 { let (x1, y1) = (0.42, 0.42 * self.slope); let t = bez_solve(x1, 0.58, p.clamp(0.0, 1.0)); let (dx, dy) = bez_dxy(x1, y1, 0.58, 1.0, t); if dx.abs() < 1e-6 { 0.0 } else { dy / dx } }
    pub fn new(now: std::time::Instant, delta: f32, dscale: f32) -> Self { let mut s = ScrollAnim { t0: now, init: 0.0, target: delta, total: 0.0, last_retarget: 0.0, slope: 0.0, applied: 0.0, dscale }; s.total = s.seg_duration(delta); s }
    fn t(&self, now: std::time::Instant) -> f32 { now.duration_since(self.t0).as_secs_f32() }
    pub fn done(&self, now: std::time::Instant) -> bool { self.t(now) >= self.total }
    pub fn value(&self, now: std::time::Instant) -> f32 { self.value_at(self.t(now)) }
    fn value_at(&self, t: f32) -> f32 {
        let dur = self.total - self.last_retarget; let tt = t - self.last_retarget;
        if dur <= 0.0 || tt >= dur { return self.target; } if tt <= 0.0 { return self.init; }
        self.init + (self.target - self.init) * self.ease(tt / dur)
    }
    fn velocity(&self, t: f32) -> f32 { let dur = self.total - self.last_retarget; if dur <= 0.0 { return 0.0; } self.ease_vel((t - self.last_retarget) / dur) * ((self.target - self.init) / dur) }
    pub fn update_target(&mut self, now: std::time::Instant, add: f32, dscale: f32) {
        self.dscale = dscale;
        let t = self.t(now).max(self.last_retarget);
        let new_target = self.target + add;
        let cur = self.value_at(t); let nd = new_target - cur;
        if nd.abs() < 0.01 { self.last_retarget = t; self.total = t; self.target = new_target; return; }
        let old_dur = self.total - self.last_retarget;
        if old_dur <= 0.0 { self.init = cur; self.target = new_target; self.last_retarget = t; self.total = t + self.seg_duration(nd); return; }
        let vel = self.velocity(t);
        let bound = if vel.abs() < 0.01 { f32::MAX } else { let b = nd / vel * 2.5; if b < 0.0 { f32::MAX } else { b } };
        let nd_dur = self.seg_duration(nd).min(bound);
        if nd_dur < 0.01 { self.target = new_target; self.total = t; return; }
        let new_slope = vel * (nd_dur / nd);
        self.slope = new_slope.clamp(-1000.0, 1000.0);
        self.init = cur; self.target = new_target; self.total = t + nd_dur; self.last_retarget = t;
    }
}

