cd /tmp/scratch/app/src; python3 - <<'PYEOF'
s=open('app.rs').read()
def rep(a,b,cnt=1):
    global s
    assert s.count(a)>=1, a[:70]
    s=s.replace(a,b,cnt)
rep("    pub fn page_links(&mut self","    #[cfg(windows)]\n    pub fn page_links(&mut self")
# ui wrapper + title
rep("    pub fn ui(&mut self, ctx: &egui::Context) {\n        let ppp = ctx.pixels_per_point();\n        self.poll();",
'''    pub fn ui(&mut self, ctx: &egui::Context) {
        let t0 = std::time::Instant::now();
        self.ui_inner(ctx);
        self.perf.frame(t0, self.view.bytes, self.view.tile_count(), self.last_sent.len());
    }
    fn ui_inner(&mut self, ctx: &egui::Context) {
        let ppp = ctx.pixels_per_point();
        self.frame += 1;
        if self.worker.is_none() { self.worker(); }
        if let Some(w) = &self.worker { if let Ok(mut g) = w.ctx.lock() { if g.is_none() { *g = Some(ctx.clone()); } } }
        self.poll();
        self.poll_render(ctx);
        self.refresh_worker(ctx);
        // tab shortcuts (consumed first so egui focus navigation does not eat Ctrl+Tab)
        let (next, prev, closew) = ctx.input_mut(|i| (i.consume_key(egui::Modifiers::COMMAND, egui::Key::Tab), i.consume_key(egui::Modifiers::COMMAND | egui::Modifiers::SHIFT, egui::Key::Tab), i.consume_key(egui::Modifiers::COMMAND, egui::Key::W)));
        let nt = self.tabs.len();
        if next && nt > 1 { let i = (self.active + 1) % nt; self.switch_to(i); }
        if prev && nt > 1 { let i = (self.active + nt - 1) % nt; self.switch_to(i); }
        if closew && self.doc.is_some() { let i = self.active; self.request_close(i); }
        let dropped: Vec<String> = ctx.input(|i| i.raw.dropped_files.iter().filter_map(|f| f.path.as_ref().map(|p| p.to_string_lossy().into_owned())).collect());
        for p in dropped { if p.to_lowercase().ends_with(".pdf") { self.open(&p); } }''')
rep("(build b3)","(build b4)")
# tab strip after the top bar panel: insert before 'if self.show_find {'
rep("        if self.show_find {\n            egui::TopBottomPanel::top(\"find\")",
'''        if self.doc.is_some() || self.tabs.len() > 1 { self.tab_strip(ctx); }
        if self.show_find {
            egui::TopBottomPanel::top("find")''')
# thumbs panel
a=s.index("        if self.show_thumbs && !self.sizes.is_empty() {")
b=s.index("        self.dialogs(ctx);")
thumb='''        self.want_bases.clear();
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
'''
s=s[:a]+thumb+s[b:]
# hover: cache only
rep("Some((pg, pp)) => self.page_chars(pg).iter().any(|c| c.c != '\\n' && c.r.expand(0.5).contains(pp)),","Some((pg, pp)) => self.text.get(&pg).map_or(false, |ch| ch.iter().any(|c| c.c != '\\n' && c.r.expand(0.5).contains(pp))),")
rep("Some((pg, pp)) => self.page_links(pg).iter().any(|(r, _)| pp.x >= r.x0 && pp.x <= r.x1 && pp.y >= r.y0 && pp.y <= r.y1),","Some((pg, pp)) => self.links.get(&pg).map_or(false, |ls| ls.iter().any(|(r, _)| pp.x >= r.x0 && pp.x <= r.x1 && pp.y >= r.y0 && pp.y <= r.y1)),")
# painting
rep("if let Some(t) = self.page_tex(ctx, i, self.zoom * ppp, settled) { painter.image(t.id(), r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE); }","self.paint_page(ctx, &painter, i, r, ppp, settled, area);")
rep("if let Some(s) = self.sel { if s.page == i { let ch = self.page_chars(i).clone(); for c in &ch[","if let Some(s) = self.sel { if s.page == i { self.page_chars(i); let ch = &self.text[&i]; for c in &ch[")
open('app.rs','w').write(s)
PYEOF
grep -n 'let ch = &self.text' app.rs | cut -c1-80; grep -n 'Msg::Reload' app.rs extras.rs | cut -c1-120
