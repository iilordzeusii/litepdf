cd /tmp/scratch/app/src; python3 - <<'PYEOF'
s=open('app.rs').read()
def rep(a,b,cnt=1):
    global s
    assert s.count(a)>=1, a[:70]
    s=s.replace(a,b,cnt)
rep('Dlg::Ocr => "OCR (English)", Dlg::None => "" };','Dlg::Ocr => "OCR (English)", Dlg::CloseTab(_) => "Unsaved changes", Dlg::None => "" };')
rep("                Dlg::None => {}\n","""                Dlg::CloseTab(i) => {
                    ui.label("This document has unsaved changes.");
                    ui.horizontal(|ui| {
                        if ui.button("Save and close").clicked() { self.save_cmd(); if !self.dirty { self.close_tab(i); } close = true; }
                        if ui.button("Discard").clicked() { self.close_tab(i); close = true; }
                        if ui.button("Cancel").clicked() { close = true; }
                    });
                }
                Dlg::None => {}
""")
# password
rep("if d.authenticate(&self.f1).unwrap_or(false) { self.set_doc(d);","if d.authenticate(&self.f1).unwrap_or(false) { self.doc_pw = Some(self.f1.clone()); self.set_doc(d);")
# Reload
a=s.index("            Msg::Reload(p, note) => {")
b=s.index("            Msg::Ai(r)")
s=s[:a]+"""            Msg::Reload(tab, p, note) => {
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
"""+s[b:]
rep("let out = self.tmp(\"ocr.pdf\"); let tx = self.tx.clone();","let out = self.tmp(\"ocr.pdf\"); let tabid = self.view.tab; let tx = self.tx.clone();")
rep("Ok(n) => Msg::Reload(out, format!(","Ok(n) => Msg::Reload(tabid, out, format!(")
rep("Ok(d) => { self.set_doc(d); self.scroll = keep.0; self.zoom = keep.1; self.dirty = moved.is_err(); }","Ok(d) => { self.set_doc_src(d, Some(src.clone())); self.scroll = keep.0; self.zoom = keep.1; self.dirty = moved.is_err(); }")
# scroll tracking
rep("            self.scroll -= sd;\n","            self.scroll -= sd;\n            if sd != 0.0 || zd != 1.0 { self.perf.active = true; }\n            self.scroll_vel = if sd != 0.0 { -sd } else { self.scroll_vel * 0.9 };\n")
rep("            if let Some((pg, f, val)) = &mut self.form_edit {","""            self.build_requests(&rects, area, ppp, settled);
            if sd == 0.0 && settled && self.last_sent.is_empty() && self.doc.is_some() && !self.sizes.is_empty() { let c = self.cur_page.min(self.sizes.len() - 1); if !self.text.contains_key(&c) { self.page_chars(c); } else if !self.links.contains_key(&c) { self.page_links(c); } }
            if let Some((pg, f, val)) = &mut self.form_edit {""")
s+=r'''
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

pub struct Perf {
    pub active: bool, any_active: bool, prev_active: bool, last_start: Option<std::time::Instant>, sec: std::time::Instant, t_run: std::time::Instant,
    frames: u32, sum_ms: f32, max_ms: f32, max_gap: f32, ups: u32, up_sum: f32, up_max: f32, rend: u32, r_sum: f32, r_max: f32, pub sync: u32, sync_max: f32, refresh_ms: f32, lines: u32, started: bool,
}
impl Perf {
    pub fn new() -> Self { let n = std::time::Instant::now(); Perf { active: false, any_active: false, prev_active: false, last_start: None, sec: n, t_run: n, frames: 0, sum_ms: 0.0, max_ms: 0.0, max_gap: 0.0, ups: 0, up_sum: 0.0, up_max: 0.0, rend: 0, r_sum: 0.0, r_max: 0.0, sync: 0, sync_max: 0.0, refresh_ms: 0.0, lines: 0, started: false } }
    pub fn upload(&mut self, ms: f32) { self.ups += 1; self.up_sum += ms; self.up_max = self.up_max.max(ms); }
    pub fn rendered(&mut self, ms: f32) { self.rend += 1; self.r_sum += ms; self.r_max = self.r_max.max(ms); }
    pub fn synced(&mut self, ms: f32) { self.sync += 1; self.sync_max = self.sync_max.max(ms); }
    pub fn refreshed(&mut self, ms: f32) { self.refresh_ms = self.refresh_ms.max(ms); }
    pub fn frame(&mut self, t0: std::time::Instant, bytes: usize, tiles: usize, queue: usize) {
        let ms = t0.elapsed().as_secs_f32() * 1000.0;
        if let Some(l) = self.last_start { let gap = t0.duration_since(l).as_secs_f32() * 1000.0; if self.prev_active && self.active && gap < 400.0 { self.max_gap = self.max_gap.max(gap); } }
        self.last_start = Some(t0); self.prev_active = self.active;
        self.frames += 1; self.sum_ms += ms; self.max_ms = self.max_ms.max(ms);
        if self.active { self.any_active = true; }
        self.active = false;
        if self.sec.elapsed().as_secs_f32() >= 1.0 {
            if (self.any_active || self.sync > 0 || self.refresh_ms > 0.0) && self.lines < 20000 {
                use std::io::Write;
                let p = extras::settings_path().with_file_name("perf.log");
                if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
                let f = if !self.started { self.started = true; std::fs::OpenOptions::new().create(true).write(true).truncate(true).open(&p) } else { std::fs::OpenOptions::new().create(true).append(true).open(&p) };
                if let Ok(mut f) = f {
                    if self.lines == 0 { let _ = writeln!(f, "LitePDF perf log (build b4). Per second while scrolling/zooming. frame = time spent inside our UI update, gap = time between consecutive frames, up = texture uploads, render = background tile render, sync = on-thread render after an edit, refresh = worker copy refresh after edit."); }
                    let _ = writeln!(f, "t={:>4}s frames={:<3} frame_avg={:.1}ms frame_max={:.1}ms gap_max={:.1}ms up={}x(max {:.1}ms) render={}x(avg {:.0}ms max {:.0}ms) sync={}x(max {:.0}ms) refresh_max={:.0}ms queue={} tex={} mem={}MB",
                        self.t_run.elapsed().as_secs(), self.frames, self.sum_ms / self.frames.max(1) as f32, self.max_ms, self.max_gap, self.ups, self.up_max, self.rend, self.r_sum / self.rend.max(1) as f32, self.r_max, self.sync, self.sync_max, self.refresh_ms, queue, tiles, bytes >> 20);
                    self.lines += 1;
                }
            }
            self.sec = std::time::Instant::now(); self.frames = 0; self.sum_ms = 0.0; self.max_ms = 0.0; self.max_gap = 0.0; self.ups = 0; self.up_sum = 0.0; self.up_max = 0.0; self.rend = 0; self.r_sum = 0.0; self.r_max = 0.0; self.sync = 0; self.sync_max = 0.0; self.refresh_ms = 0.0; self.any_active = false;
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
        let o = pos2((r.min.x * ppp).round() / ppp, (r.min.y * ppp).round() / ppp);
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
        if let Some(b) = self.view.bases.get_mut(&i) { b.stamp = self.frame; painter.image(b.tex.id(), r, uv, Color32::WHITE); } else { painter.rect_filled(r, 0.0, Color32::WHITE); }
        if self.doc.is_none() { return; }
        let (sk, f, o, grid) = self.tile_grid(i, r, ppp);
        let ssc = self.zoom * ppp;
        let required = self.view.required(i);
        let awaiting = required > self.view.rev;
        let vis: Vec<(u16, u16, Rect)> = grid.into_iter().filter(|(_, _, tr)| tr.intersects(area)).collect();
        // edits not yet in the worker's copy: render the visible tiles right here so the change shows at once
        if awaiting && self.perf.sync < 8 {
            for (tx, ty, _) in &vis {
                if self.tile_missing(i, sk, *tx, *ty) {
                    let t0 = std::time::Instant::now();
                    let done = (|| -> Option<(usize, usize, Vec<u8>)> {
                        let doc = self.doc.as_ref()?; let pg = doc.load_page(i as i32).ok()?; let b = pg.bounds().ok()?;
                        let l = pg.to_display_list(true).ok()?;
                        render::render_job_doc(doc, &l, (b.x1 - b.x0, b.y1 - b.y0), Kind::Tile { key: sk, tx: *tx, ty: *ty })
                    })();
                    if let Some((w, h, rgba)) = done { self.put_tile(ctx, i, Some((sk, *tx, *ty)), w, h, &rgba, required); }
                    self.perf.synced(t0.elapsed().as_secs_f32() * 1000.0);
                }
            }
        }
        let have_all = vis.iter().all(|(tx, ty, _)| !self.tile_missing(i, sk, *tx, *ty));
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
        let mut budget = UPLOAD_BUDGET; let mut more = false;
        loop {
            let Some(w) = self.worker.as_ref() else { break };
            if budget == 0 { more = true; break; }
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
                Res::Failed { tab, epoch, msg } => { if tab == self.view.tab && epoch == self.view.epoch { self.status = format!("Render failed: {msg}"); } }
                Res::Img { job, rev, w, h, rgba, ms } => {
                    self.perf.rendered(ms);
                    if job.tab != self.view.tab || job.epoch != self.view.epoch { continue; }
                    if rev < self.view.required(job.page) { continue; }
                    let tile = match job.kind { Kind::Tile { key, tx, ty } => { if key != cur_key { continue; } Some((key, tx, ty)) } Kind::Base => None };
                    let t0 = std::time::Instant::now();
                    self.put_tile(ctx, job.page, tile, w, h, &rgba, rev);
                    budget = budget.saturating_sub(w * h * 4);
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
        if std::time::Instant::now() < due || ctx.input(|i| i.pointer.any_down()) { ctx.request_repaint_after(std::time::Duration::from_millis(120)); return; }
        self.view.refresh_due = None;
        let t0 = std::time::Instant::now();
        let mut buf: Vec<u8> = vec![];
        if let Some(d) = &self.doc { if d.write_to(&mut buf).is_err() { return; } }
        self.view.rev += 1;
        let (tab, epoch, rev, pw) = (self.view.tab, self.view.epoch, self.view.rev, self.view.pw.clone());
        self.last_sent.clear();
        self.worker().tx.send(Cmd::Open { tab, epoch, rev, src: Src::Bytes(buf), pw, want_sizes: false }).ok();
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
        for &i in &self.want_bases { if i < n && self.view.required(i) <= self.view.rev && base_missing(self, i) { v.push((1, 0.0, Job { tab, epoch, page: i, kind: Kind::Base })); } }
        v.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal)));
        v.truncate(90);
        let jobs: Vec<Job> = v.into_iter().map(|x| x.2).collect();
        let set: HashSet<Job> = jobs.iter().copied().collect();
        if set != self.last_sent { self.last_sent = set; self.worker().tx.send(Cmd::Want(jobs)).ok(); }
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
        self.worker().tx.send(Cmd::Close { tab: id }).ok();
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
'''
open('app.rs','w').write(s)
PYEOF
grep -n '^mod\|^use' main.rs | head; sed -i 's/^mod crash;/mod crash;\nmod render;/' main.rs; cd ..; source /tmp/scratch/wenv.sh; cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E '^(error|warning: unused)' -A7 | head -120
