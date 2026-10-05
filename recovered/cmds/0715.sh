cd /tmp/scratch/app/src; python3 - <<'PYEOF'
r=open('render.rs').read()
def repr_(x,y):
    global r
    assert x in r,x[:60]; r=r.replace(x,y,1)
repr_("    Failed { tab: u32, epoch: u32, msg: String },","    Failed { tab: u32, epoch: u32, msg: String },\n    JobFailed { job: Job, why: &'static str },")
repr_("        if d.epoch != job.epoch { continue; }","        if d.epoch != job.epoch { let _ = tx.send(Res::JobFailed { job, why: \"worker has an older/newer document epoch\" }); wake(&ctx); continue; }")
repr_("""                if let Some((w, h, rgba, list_ms, hit)) = render_job(d, &job) {
                    let _ = tx.send(Res::Img { job, rev: d.rev, w, h, rgba, ms: t.elapsed().as_secs_f32() * 1000.0, list_ms, hit, wid: id });
                    wake(&ctx);
                }""","""                if let Some((w, h, rgba, list_ms, hit)) = render_job(d, &job) {
                    let _ = tx.send(Res::Img { job, rev: d.rev, w, h, rgba, ms: t.elapsed().as_secs_f32() * 1000.0, list_ms, hit, wid: id });
                    wake(&ctx);
                } else { let _ = tx.send(Res::JobFailed { job, why: "render returned nothing (page load or pixmap failure)" }); wake(&ctx); }""")
repr_("                if let Some((chars, links)) = extract_text(d, job.page) { let _ = tx.send(Res::Text { job, rev: d.rev, chars, links, ms: t.elapsed().as_secs_f32() * 1000.0 }); wake(&ctx); }","                if let Some((chars, links)) = extract_text(d, job.page) { let _ = tx.send(Res::Text { job, rev: d.rev, chars, links, ms: t.elapsed().as_secs_f32() * 1000.0 }); wake(&ctx); } else { let _ = tx.send(Res::JobFailed { job, why: \"text extraction failed\" }); wake(&ctx); }")
open('render.rs','w').write(r)
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a,x[:60]; a=a.replace(x,y,1)
rep("pub zrem: f32,","pub zrem: f32, pub miss_frame: usize, pub miss_last: usize, pub last_res: std::time::Instant, pub watchdog: u32,")
rep("zrem: 0.0,","zrem: 0.0, miss_frame: 0, miss_last: 0, last_res: std::time::Instant::now(), watchdog: 0,")
rep("        let t0 = std::time::Instant::now();\n        self.ui_inner(ctx);","        let t0 = std::time::Instant::now();\n        self.miss_frame = 0;\n        self.ui_inner(ctx);\n        self.miss_last = self.miss_frame;\n        // watchdog: visible tiles are missing but nothing has arrived for a while -> resend the whole request list\n        if self.miss_last > 0 && self.last_res.elapsed().as_millis() > 400 && self.doc.is_some() { self.last_res = std::time::Instant::now(); self.last_sent.clear(); self.watchdog += 1; if self.watchdog <= 50 { self.perf.note(format!(\"WATCHDOG: {} visible tiles still missing with no results for 400 ms, resending the request list\", self.miss_last)); } ctx.request_repaint(); }")
rep("        let have_all = vis.iter().all(|(tx, ty, _)| !self.tile_missing(i, sk, *tx, *ty));","        let n_missing = vis.iter().filter(|(tx, ty, _)| self.tile_missing(i, sk, *tx, *ty)).count();\n        let have_all = n_missing == 0;\n        if !have_all { self.miss_frame += n_missing; }")
rep("                Res::Failed { tab, epoch, msg } =>","                Res::JobFailed { job, why } => { self.perf.note(format!(\"worker job failed: page {} {:?}: {why}\", job.page + 1, job.kind)); self.last_sent.clear(); }\n                Res::Failed { tab, epoch, msg } =>")
rep("                Res::Img { job, rev, w, h, rgba, ms, list_ms, hit, wid } => {","                Res::Img { job, rev, w, h, rgba, ms, list_ms, hit, wid } => {\n                    self.last_res = std::time::Instant::now();")
open('app.rs','w').write(a)
PYEOF
grep -n 'rev < self.view.required(job.page) { self.last_sent.clear(); continue; }' app.rs | head
