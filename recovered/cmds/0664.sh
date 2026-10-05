cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a, x[:70]
    a=a.replace(x,y,1)
rep("let mut budget = UPLOAD_BUDGET; let mut more = false;","let fast = self.diag.upload1 && self.scroll_vel.abs() > 25.0;\n        let mut budget = if fast { 4_200_000usize } else { UPLOAD_BUDGET }; let mut more = false;")
rep("""                Res::Img { job, rev, w, h, rgba, ms } => {
                    self.perf.rendered(ms);
                    if job.tab != self.view.tab || job.epoch != self.view.epoch { continue; }
                    if rev < self.view.required(job.page) { continue; }
                    let tile = match job.kind { Kind::Tile { key, tx, ty } => { if key != cur_key { continue; } Some((key, tx, ty)) } Kind::Base => None };
                    let t0 = std::time::Instant::now();
                    self.put_tile(ctx, job.page, tile, w, h, &rgba, rev);
                    budget = budget.saturating_sub(w * h * 4);""","""                Res::Text { job, rev, chars, links, ms } => {
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
                    self.perf.worker_job(wid, match job.kind { Kind::Base => "base", _ => "tile" }, job.page, ms, list_ms, hit);
                    if job.tab != self.view.tab || job.epoch != self.view.epoch { continue; }
                    if rev < self.view.required(job.page) { self.last_sent.clear(); continue; }
                    let tile = match job.kind { Kind::Tile { key, tx, ty } => { if key != cur_key { continue; } Some((key, tx, ty)) } _ => None };
                    let t0 = std::time::Instant::now();
                    self.put_tile(ctx, job.page, tile, w, h, &rgba, rev);
                    budget = budget.saturating_sub(if tile.is_none() && fast { w * h * 2 } else { w * h * 4 });""")
# build requests: text jobs
rep("        for &i in &self.want_bases {","""        // text + links for the pages being looked at, extracted on the workers (never on the UI thread)
        if self.view.rev >= self.view.rev_all {
            let cp = self.cur_page;
            for i in [cp, cp + 1, cp.saturating_sub(1)] { if i < n && !(self.text.contains_key(&i) && self.links.contains_key(&i)) && self.view.required(i) <= self.view.rev { v.push((5, (rects[i].center().y - cy).abs(), Job { tab, epoch, page: i, kind: Kind::Text })); } }
        }
        for &i in &self.want_bases {""")
# paint_page: snap, vis, sync_mode
rep("let o = pos2((r.min.x * ppp).round() / ppp, (r.min.y * ppp).round() / ppp);","let o = if self.diag.snap { pos2((r.min.x * ppp).round() / ppp, (r.min.y * ppp).round() / ppp) } else { r.min };")
rep("if let Some(b) = self.view.bases.get_mut(&i) { b.stamp = self.frame; painter.image(b.tex.id(), r, uv, Color32::WHITE); } else { painter.rect_filled(r, 0.0, Color32::WHITE); }",
"let rs = if self.diag.snap { Rect::from_min_size(pos2((r.min.x * ppp).round() / ppp, (r.min.y * ppp).round() / ppp), r.size()) } else { r };\n        let has_base = self.view.bases.contains_key(&i);\n        if let Some(b) = self.view.bases.get_mut(&i) { b.stamp = self.frame; painter.image(b.tex.id(), rs, uv, Color32::WHITE); } else { painter.rect_filled(r, 0.0, Color32::WHITE); }")
rep("if awaiting && self.perf.sync_frame < 1 {","if (awaiting || self.diag.sync_mode) && self.perf.sync_frame < 1 {")
rep("        let _ = f;\n    }","        let _ = f;\n        if r.intersects(area) { let sharp = self.view.tiles.get(&i).map_or(false, |m| vis.iter().all(|(tx, ty, _)| m.contains_key(&(sk, *tx, *ty)))); self.perf.vis(if sharp { 2 } else if has_base { 1 } else { 0 }); }\n    }")
# menu
rep("""        if ui.selectable_label(self.show_ai, "AI")""","""        ui.menu_button("Diagnostics", |ui| {
            ui.label("Live switches for lag hunting. Log: perf.log in %APPDATA%\\\\LitePDF");
            ui.checkbox(&mut self.diag.raw_wheel, "Raw touchpad/wheel (off = egui eased scroll)");
            ui.checkbox(&mut self.diag.sync_mode, "Render visible tiles on the UI thread (build b3 behaviour)");
            ui.checkbox(&mut self.diag.snap, "Snap pages and tiles to whole pixels");
            ui.checkbox(&mut self.diag.upload1, "Limit uploads to ~1 tile per frame while scrolling fast");
            let mut gf = self.gl_finish.load(std::sync::atomic::Ordering::Relaxed);
            if ui.checkbox(&mut gf, "Wait for GPU each frame (glFinish)").changed() { self.gl_finish.store(gf, std::sync::atomic::Ordering::Relaxed); }
            ui.label("Restart with --vsync=off to test without vsync.");
        });
        if ui.selectable_label(self.show_ai, "AI")""")
open('app.rs','w').write(a)
m=open('main.rs').read()
m=m.replace("fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) { self.0.ui(ctx); }","fn update(&mut self, ctx: &egui::Context, f: &mut eframe::Frame) { self.0.ui(ctx); if self.0.gl_finish.load(std::sync::atomic::Ordering::Relaxed) { if let Some(gl) = f.gl() { use eframe::glow::HasContext; unsafe { gl.finish(); } } } }")
m=m.replace("let opts = eframe::NativeOptions {","let vsync = !argv.iter().any(|s| s == \"--vsync=off\");\n    let opts = eframe::NativeOptions { vsync,")
m=m.replace("eframe::run_native(\"LitePDF\", opts, Box::new(|_| Ok(Box::new(Wrap(app)))))","""eframe::run_native("LitePDF", opts, Box::new(move |cc| {
        let mut app = app;
        if let Some(gl) = cc.gl.as_ref() { use eframe::glow::HasContext; let (r, v) = unsafe { (gl.get_parameter_string(eframe::glow::RENDERER), gl.get_parameter_string(eframe::glow::VENDOR)) }; app.perf.header = format!("GL renderer: {r} | vendor: {v} | vsync: {}", if vsync { "on" } else { "off" }); }
        #[cfg(windows)] { app.gpu_pref_probe(); }
        Ok(Box::new(Wrap(app)))
    }))""")
open('main.rs','w').write(m)
PYEOF
grep -n 'Perf::new\|"build b4"' app.rs | head -3
