cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y,c=1):
    global a
    assert x in a,x[:70]; a=a.replace(x,y,c)
rep("fn seg_duration(delta: f32) -> f32 { (14.0 - delta.abs() / 60.0).clamp(6.0, 12.0) / 60.0 }","fn seg_duration(&self, delta: f32) -> f32 { (14.0 - delta.abs() / 60.0).clamp(6.0, 12.0) / 60.0 * self.dscale }")
rep("slope: f32, pub applied: f32 }","slope: f32, pub applied: f32, dscale: f32 }")
rep("pub fn new(now: std::time::Instant, delta: f32) -> Self { ScrollAnim { t0: now, init: 0.0, target: delta, total: Self::seg_duration(delta), last_retarget: 0.0, slope: 2.0, applied: 0.0 } }","pub fn new(now: std::time::Instant, delta: f32, dscale: f32) -> Self { let mut s = ScrollAnim { t0: now, init: 0.0, target: delta, total: 0.0, last_retarget: 0.0, slope: 2.0, applied: 0.0, dscale }; s.total = s.seg_duration(delta); s }")
rep("self.total = t + Self::seg_duration(nd); return;","self.total = t + self.seg_duration(nd); return;")
rep("let nd_dur = Self::seg_duration(nd).min(bound);","let nd_dur = self.seg_duration(nd).min(bound);")
rep("pub fn update_target(&mut self, now: std::time::Instant, add: f32) {","pub fn update_target(&mut self, now: std::time::Instant, add: f32, dscale: f32) {\n        self.dscale = dscale;")
rep("s.update_target(now, notch_in)","s.update_target(now, notch_in, self.diag.tp_tau)")
rep("Some(ScrollAnim::new(now, notch_in))","Some(ScrollAnim::new(now, notch_in, self.diag.tp_tau))")
rep("tp_gain: 1.0, tp_tau: 35.0,","tp_gain: 1.0, tp_tau: 0.5,")
rep('            ui.add(egui::Slider::new(&mut self.diag.tp_gain','            ui.add(egui::Slider::new(&mut self.diag.tp_tau, 0.1..=1.5).text("Scroll smoothing length (1.0 = Chromium)"));\n            ui.add(egui::Slider::new(&mut self.diag.tp_gain')
open('app.rs','w').write(a)
PYEOF
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A12 | head -30
