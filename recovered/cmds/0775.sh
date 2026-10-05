cd /tmp/scratch/app/src; cp app.rs /tmp/app.rs.b12; python3 - <<'EOF'
s=open('app.rs').read()
def rep(a,b):
    global s
    assert a in s,a[:70]
    s=s.replace(a,b,1)
rep("pub tvel: f32,","pub tvel: f32, pub tsamp: Vec<(std::time::Instant, f32)>,")
rep("tvel: 0.0,","tvel: 0.0, tsamp: Vec::new(),")
rep("pub rec: bool }","pub rec: bool, pub tp_sens: f32, pub z_sens: f32 }")
rep("rec: false } } }","rec: false, tp_sens: 0.7, z_sens: 1.0 } } }")
rep("let hh = area.height();","let hh = area.height(); let zs = self.diag.z_sens;")
rep("zw += (px / 100.0).exp().clamp(0.75, 1.25).ln(); }","zw += (px / 100.0 * zs).clamp(-0.4, 0.4); }")
rep("tp_px += v * sys_lines() * (100.0 / 3.0) * self.diag.tp_gain;","tp_px += v * sys_lines() * (100.0 / 3.0) * self.diag.tp_gain * self.diag.tp_sens;")
rep("egui::MouseWheelUnit::Point => tp_px += delta.y,","egui::MouseWheelUnit::Point => tp_px += delta.y * self.diag.tp_sens,")
a=s.index("            { let now = std::time::Instant::now(); let dtm = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);\n              if tp_px != 0.0")
b=s.index("            let raw_total = req + notch_in + tp_px;")
new="""            { let now = std::time::Instant::now(); let dtm = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);
              // any other input (pointer move, click/tap, touch, key) stops the momentum at once
              let other = ui.input(|i| i.pointer.delta() != Vec2::ZERO || i.events.iter().any(|e| matches!(e, egui::Event::PointerButton { .. } | egui::Event::Touch { .. } | egui::Event::Key { .. } | egui::Event::Text(_))));
              if other || notch_in != 0.0 || req != 0.0 { self.tvel = 0.0; self.tsamp.clear(); }
              if tp_px != 0.0 { self.tsamp.push((now, tp_px)); self.tlast = now; self.tvel = 0.0; }
              else if !self.tsamp.is_empty() {
                  let gap = now.duration_since(self.tlast).as_millis();
                  if gap > 45 {
                      // release: velocity = distance over the last 80 ms of events (measured, so momentum is proportional to swipe speed)
                      let t_end = self.tlast; let win = std::time::Duration::from_millis(80);
                      let sum: f32 = self.tsamp.iter().filter(|(t, _)| t_end.duration_since(*t) <= win).map(|(_, p)| *p).sum();
                      let first = self.tsamp.iter().filter(|(t, _)| t_end.duration_since(*t) <= win).map(|(t, _)| *t).min().unwrap_or(t_end);
                      let span = t_end.duration_since(first).as_secs_f32().max(0.04);
                      let v = sum / span; self.tsamp.clear();
                      self.tvel = if v.abs() > 150.0 { v } else { 0.0 };
                  } else { self.tsamp.retain(|(t, _)| now.duration_since(*t).as_millis() < 200); ctx.request_repaint(); }
              }
              if self.tvel != 0.0 && tp_px == 0.0 { if self.tvel.abs() > 60.0 { mom = self.tvel * dtm; self.tvel *= (-dtm / 0.325).exp(); ctx.request_repaint(); } else { self.tvel = 0.0; } } }
"""
s=s[:a]+new+s[b:]
# zoom_step: faster
rep("let cap = 3.5 * dt; let step = (d * (1.0 - (-dt / 0.05).exp())).clamp(-cap, cap);","let cap = 10.0 * dt; let step = (d * (1.0 - (-dt / 0.02).exp())).clamp(-cap, cap);")
rep("exponential approach (tau 50 ms) with a hard cap of 3.5 ln-units/s","exponential approach (tau 20 ms) with a hard cap of 10 ln-units/s")
rep('ui.checkbox(&mut self.diag.rec,','ui.add(egui::Slider::new(&mut self.diag.tp_sens, 0.2..=1.5).text("Touchpad scroll sensitivity (touchpad only)"));\n            ui.add(egui::Slider::new(&mut self.diag.z_sens, 0.2..=2.0).text("Pinch zoom sensitivity (1.0 = Chromium exp(delta/100))"));\n            ui.checkbox(&mut self.diag.rec,')
s=s.replace("(build b12)","(build b13)")
open('app.rs','w').write(s)
EOF
grep -n 'use egui\|Vec2' app.rs | head -3
sed -i 's/(build b12)/(build b13)/' app.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error|Finished' -A9
