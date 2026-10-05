cd /tmp/scratch/app/src; python3 - <<'PYEOF'
s=open('render.rs').read()
s=s.replace("        Kind::Text => return None,\n        Kind::Text => return None,\n","        Kind::Text => return None,\n")
open('render.rs','w').write(s)
a=open('app.rs').read()
def rep(x,y,cnt=1):
    global a
    assert a.count(x)>=1, x[:80]
    a=a.replace(x,y,cnt)
rep("self.worker().tx.send(Cmd::Open { tab, epoch, rev: 0, src, pw, want_sizes: true }).ok();","self.worker().send(Cmd::Open { tab, epoch, rev: 0, src, pw, want_sizes: true });")
rep("None => { let mut buf: Vec<u8> = vec![]; let _ = d.write_to(&mut buf); Src::Bytes(buf) } };","None => { let mut buf: Vec<u8> = vec![]; let _ = d.write_to(&mut buf); Src::Bytes(std::sync::Arc::new(buf)) } };")
rep("self.worker().tx.send(Cmd::Open { tab, epoch, rev, src: Src::Bytes(buf), pw, want_sizes: false }).ok();","self.worker().send(Cmd::Open { tab, epoch, rev, src: Src::Bytes(std::sync::Arc::new(buf)), pw, want_sizes: false });")
rep("self.worker().tx.send(Cmd::Want(jobs)).ok();","self.worker().send(Cmd::Want(jobs));")
rep("self.worker().tx.send(Cmd::Close { tab: id }).ok();","self.worker().send(Cmd::Close { tab: id });")
rep("(build b4)","(build b5)")
# struct fields
rep("    pub perf: Perf, pub prev_scroll: f32, pub scroll_vel: f32,\n","    pub perf: Perf, pub prev_scroll: f32, pub scroll_vel: f32,\n    pub diag: Diag, pub notch: f32, pub swipe: Option<Swipe>, pub gl_finish: std::sync::Arc<std::sync::atomic::AtomicBool>,\n")
rep("perf: Perf::new(), prev_scroll: 0.0, scroll_vel: 0.0, ","perf: Perf::new(), prev_scroll: 0.0, scroll_vel: 0.0, diag: Diag::default(), notch: 0.0, swipe: None, gl_finish: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)), ")
# stage marks in ui_inner
rep("        self.poll();\n        self.poll_render(ctx);\n        self.refresh_worker(ctx);\n","        self.perf.begin(); self.poll();\n        self.poll_render(ctx);\n        self.perf.mark(\"poll\");\n        self.refresh_worker(ctx);\n        self.perf.mark(\"refresh\");\n")
rep("        self.want_bases.clear();\n","        self.perf.mark(\"top panels\");\n        self.want_bases.clear();\n")
rep("        self.dialogs(ctx);\n        self.sign_pad(ctx);","        self.perf.mark(\"thumbs\");\n        self.dialogs(ctx);\n        self.sign_pad(ctx);")
# wheel
old_start=a.index("            let sd = ui.input(|i| i.smooth_scroll_delta.y);")
old_end=a.index("            if let Some(t) = self.want_scroll_to.take()")
new_wheel='''            // touchpad / wheel: read the raw events ourselves (egui's own easing is a ~43 ms low-pass plus coasting)
            let over = resp.hovered() || resp.dragged();
            let mut req = 0.0f32; let mut notch_in = 0.0f32;
            if over { let evs: Vec<egui::Event> = ui.input(|i| i.events.clone()); for e in evs { if let egui::Event::MouseWheel { unit, delta, modifiers, .. } = e {
                if modifiers.command || modifiers.ctrl || modifiers.shift || modifiers.alt { continue; }
                match unit {
                    egui::MouseWheelUnit::Line => { if delta.y.abs() >= 0.5 { notch_in += delta.y * 90.0; } else { req += delta.y * 40.0; } }
                    egui::MouseWheelUnit::Page => req += delta.y * area.height(),
                    egui::MouseWheelUnit::Point => req += delta.y,
                }
            } } }
            if notch_in != 0.0 { self.notch += notch_in; }
            let mut rel = 0.0f32;
            if self.notch != 0.0 { let dt = ui.input(|i| i.stable_dt).clamp(0.001, 0.05); rel = if self.notch.abs() < 0.5 { self.notch } else { self.notch * (1.0 - (-dt / 0.03).exp()) }; self.notch -= rel; if self.notch != 0.0 { ctx.request_repaint(); } }
            let raw_total = req + notch_in;
            let sd = if self.diag.raw_wheel { req + rel } else if over { ui.input(|i| i.smooth_scroll_delta.y) } else { 0.0 };
            self.scroll -= sd;
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
                        self.perf.note(format!("wheel swipe: requested {:.0} pt, first movement after {:.0} ms, 90% applied after {:.0} ms, 99% after {:.0} ms ({} mode)", sw.req, first, t_at(0.9), t_at(0.99), if self.diag.raw_wheel { "raw" } else { "egui-eased" })); }
                } else { ctx.request_repaint_after(std::time::Duration::from_millis(60)); }
            }
            if sd != 0.0 || zd != 1.0 { self.perf.active = true; }
            self.scroll_vel = if sd != 0.0 { -sd } else { self.scroll_vel * 0.9 };
'''
a=a[:old_start]+new_wheel+a[old_end:]
# remove idle extraction line, add marks
i=a.index("            self.build_requests(&rects, area, ppp, settled);")
j=a.index("            if let Some((pg, f, val)) = &mut self.form_edit {")
a=a[:i]+"            self.perf.mark(\"paint\");\n            self.build_requests(&rects, area, ppp, settled);\n            self.perf.mark(\"requests\");\n"+a[j:]
open('app.rs','w').write(a)
PYEOF
grep -n 'let sd\|self.scroll -= sd' app.rs | head
