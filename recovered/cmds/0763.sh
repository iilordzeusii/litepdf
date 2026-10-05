cd /tmp/scratch/app/src; cp app.rs /tmp/app.rs.b11; python3 - <<'EOF'
import re
s=open('app.rs').read()
def rep(a,b,cnt=1):
    global s
    assert s.count(a)>=1,(a[:60])
    s=s.replace(a,b,cnt)
# fields
rep("pub zrem: f32,","pub zrem: f32, pub ztarget: f32, pub zlast: f32, pub tvel: f32, pub tlast: std::time::Instant,")
rep("zrem: 0.0,","zrem: 0.0, ztarget: 0.0, zlast: 1.0, tvel: 0.0, tlast: std::time::Instant::now(),")
rep("pub upload1: bool }","pub upload1: bool, pub rec: bool }")
rep("upload1: true } } }","upload1: true, rec: false } } }")
# zoom block
a=s.index("            self.zrem += zn;")
b=s.index("\n",s.index("zd0 * take.exp() };",a))
new="""            // Target zoom is driven by the events; the displayed zoom follows it every frame (zoom_step), starting on the first frame.
            if self.ztarget <= 0.0 || (self.zoom / self.zlast - 1.0).abs() > 1e-4 { self.ztarget = self.zoom; }
            self.ztarget = (self.ztarget * zd0 * zn.exp()).clamp(0.1, 8.0);
            let zdt = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);
            let zd = { let nz = zoom_step(self.zoom, self.ztarget, zdt); if nz != self.ztarget { ctx.request_repaint(); } nz / self.zoom };"""
s=s[:a]+new+s[b:]
rep("let settled = true;","self.zlast = self.zoom; let settled = true;")
# scroll classification
rep("egui::MouseWheelUnit::Line => { notch_in += delta.y * 100.0 * self.diag.tp_gain; }",
"egui::MouseWheelUnit::Line => { let v = delta.y; let a = v.abs(); if a >= 0.99 && (a - a.round()).abs() < 0.01 { notch_in += v * 100.0 * self.diag.tp_gain; } else { tp_px += v * 100.0 * self.diag.tp_gain; } }")
rep("egui::MouseWheelUnit::Point => req += delta.y,","egui::MouseWheelUnit::Point => tp_px += delta.y,")
rep("let mut req = 0.0f32; let mut notch_in = 0.0f32;","let mut req = 0.0f32; let mut notch_in = 0.0f32; let mut tp_px = 0.0f32;")
rep("let raw_total = req + notch_in;\n            let sd = req + rel;",
"""// touchpad (fine deltas): applied directly like Chromium's precise path, plus a decaying momentum after the stream stops
            let mut mom = 0.0f32;
            { let now = std::time::Instant::now(); let dtm = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);
              if tp_px != 0.0 { let inst = tp_px / dtm; self.tvel = if self.tvel * inst > 0.0 { 0.5 * self.tvel + 0.5 * inst } else { inst }; self.tlast = now; }
              else if notch_in != 0.0 || req != 0.0 { self.tvel = 0.0; }
              else if self.tvel != 0.0 { if now.duration_since(self.tlast).as_millis() > 45 { if self.tvel.abs() > 120.0 { mom = self.tvel * dtm; self.tvel *= (-dtm / 0.325).exp(); ctx.request_repaint(); } else { self.tvel = 0.0; } } else { ctx.request_repaint(); } } }
            let raw_total = req + notch_in + tp_px;
            let sd = req + rel + tp_px + mom;""")
# recorder + zoom_step fn
rep("self.scroll -= sd;","""self.scroll -= sd;
            if self.diag.rec { let t0 = *REC_T0.get_or_init(std::time::Instant::now); let tm = t0.elapsed().as_secs_f32() * 1000.0;
                let mut out = String::new();
                ui.input(|i| { for e in &i.events { match e {
                    egui::Event::MouseWheel { unit, delta, modifiers, .. } => out.push_str(&format!("{:.1} wheel unit={:?} dx={:.4} dy={:.4} ctrl={} shift={} alt={}\\n", tm, unit, delta.x, delta.y, modifiers.ctrl, modifiers.shift, modifiers.alt)),
                    egui::Event::Zoom(f) => out.push_str(&format!("{:.1} zoom_event factor={:.5}\\n", tm, f)),
                    egui::Event::Touch { phase, pos, force, .. } => out.push_str(&format!("{:.1} touch {:?} {:.0},{:.0} force={:?}\\n", tm, phase, pos.x, pos.y, force)),
                    _ => {} } } });
                if !out.is_empty() || sd != 0.0 || zd != 1.0 || self.ztarget != self.zoom { out.push_str(&format!("{:.1} frame dt={:.2}ms sd={:.2} (touchpad {:.2} wheel-anim {:.2} momentum {:.2}) scroll={:.1} zoom={:.4} ztarget={:.4} tvel={:.0}\\n", tm, ui.input(|i| i.unstable_dt) * 1000.0, sd, tp_px, rel, mom, self.scroll, self.zoom, self.ztarget, self.tvel)); }
                if !out.is_empty() { use std::io::Write; let p = extras::settings_path().with_file_name("input.log"); if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) { let _ = f.write_all(out.as_bytes()); } } }""")
rep("pub struct ScrollAnim {","""static REC_T0: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
/// Moves the displayed zoom toward the target in log space: exponential approach (tau 50 ms) with a hard cap of 3.5 ln-units/s,
/// both scaled by the frame time, so the shown zoom passes through every intermediate value on any refresh rate.
pub fn zoom_step(cur: f32, target: f32, dt: f32) -> f32 {
    let d = (target / cur).ln(); if d.abs() < 1e-4 { return target; }
    let cap = 3.5 * dt; let step = (d * (1.0 - (-dt / 0.05).exp())).clamp(-cap, cap); cur * step.exp()
}
pub struct ScrollAnim {""")
s=s.replace("(build b11)","(build b12)")
open('app.rs','w').write(s)
EOF
grep -n 'z_tau' app.rs | head -3; grep -n 'Slider::new(&mut self.diag.tp_gain' app.rs | cut -c1-200
