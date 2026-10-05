cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a,x[:70]; a=a.replace(x,y,1)
# zoom: Chromium gesture_detector.ts
rep("zn += pts / 200.0;","{ let px = match unit { egui::MouseWheelUnit::Line => (delta.x + delta.y) * 100.0, egui::MouseWheelUnit::Page => (delta.x + delta.y) * hh, egui::MouseWheelUnit::Point => delta.x + delta.y }; let _ = pts; z *= (px / 100.0).exp().clamp(0.75, 1.25); }")
i=a.index("            let zd = {\n                let dt = ui.input(|i| i.unstable_dt)"); j=a.index("zd0 * rel.exp() };",i)+len("zd0 * rel.exp() };")
a=a[:i]+"            let _ = zn; let zd = zd0; // Chromium applies each ctrl-wheel / pinch step directly, no easing"+a[j:]
# scroll: all line deltas -> Chromium wheel animation
rep("egui::MouseWheelUnit::Line => { if is_notch(delta.y) { notch_in += delta.y * 100.0; } else { req += delta.y * self.diag.tp_gain; } }","egui::MouseWheelUnit::Line => { notch_in += delta.y * 100.0 * self.diag.tp_gain; }")
i=a.index("            { let dtm = ui.input(|i| i.unstable_dt)"); j=a.index("\n",a.index("self.mrem != 0.0 { ctx.request_repaint(); } } }",i))
a=a[:i]+"""            { let now = std::time::Instant::now();
              if notch_in != 0.0 { match &mut self.sanim2 { Some(s) if !s.done(now) => s.update_target(now, notch_in), _ => { self.sanim2 = Some(ScrollAnim::new(now, notch_in)); } } }
              if let Some(s) = &mut self.sanim2 { let v = s.value(now); rel = v - s.applied; s.applied = v; if s.done(now) { self.sanim2 = None; } else { ctx.request_repaint(); } } }"""+a[j:]
rep("            // touchpad: instant-start exponential follow (moves a share of the remaining distance on the very first frame)\n            let dt = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);\n            self.notch += req;\n            let mut tp = 0.0f32;\n            if self.notch != 0.0 { tp = if self.notch.abs() < 0.3 { self.notch } else { self.notch * (1.0 - (-dt / (self.diag.tp_tau / 1000.0)).exp()) }; self.notch -= tp; if self.notch != 0.0 { ctx.request_repaint(); } }\n            let sd = tp + rel;","            let sd = req + rel;")
rep("pub zrem: f32,","pub sanim2: Option<ScrollAnim>, pub zrem: f32,")
rep("zrem: 0.0,","sanim2: None, zrem: 0.0,")
rep("tp_gain: 22.0, tp_tau: 35.0, z_gain: 1.0, z_tau: 35.0,","tp_gain: 1.0, tp_tau: 35.0, z_gain: 1.0, z_tau: 35.0,")
i=a.index('            ui.add(egui::Slider::new(&mut self.diag.tp_gain'); j=a.index('            ui.checkbox(&mut self.diag.overlay,')
a=a[:i]+'            ui.add(egui::Slider::new(&mut self.diag.tp_gain, 0.2..=3.0).text("Scroll distance (1.0 = Chromium: 100 px per wheel tick)"));\n'+a[j:]
a+='''
/// Port of Chromium's cc::ScrollOffsetAnimationCurve for mouse-wheel scrolls (ease-in-out cubic bezier 0.42,0,0.58,1,
/// kInverseDelta duration 6..12 frames at 60 Hz, UpdateTarget keeps the current velocity). One deliberate change: a brand
/// new animation starts with a non-zero initial slope so it moves on the first frame instead of easing in from rest.
pub struct ScrollAnim { t0: std::time::Instant, init: f32, target: f32, total: f32, last_retarget: f32, slope: f32, pub applied: f32 }
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
    fn seg_duration(delta: f32) -> f32 { (14.0 - delta.abs() / 60.0).clamp(6.0, 12.0) / 60.0 }
    fn ease(&self, p: f32) -> f32 { let (x1, y1) = (0.42, 0.42 * self.slope); let t = bez_solve(x1, 0.58, p); bez_xy(x1, y1, 0.58, 1.0, t).1 }
    fn ease_vel(&self, p: f32) -> f32 { let (x1, y1) = (0.42, 0.42 * self.slope); let t = bez_solve(x1, 0.58, p.clamp(0.0, 1.0)); let (dx, dy) = bez_dxy(x1, y1, 0.58, 1.0, t); if dx.abs() < 1e-6 { 0.0 } else { dy / dx } }
    pub fn new(now: std::time::Instant, delta: f32) -> Self { ScrollAnim { t0: now, init: 0.0, target: delta, total: Self::seg_duration(delta), last_retarget: 0.0, slope: 2.0, applied: 0.0 } }
    fn t(&self, now: std::time::Instant) -> f32 { now.duration_since(self.t0).as_secs_f32() }
    pub fn done(&self, now: std::time::Instant) -> bool { self.t(now) >= self.total }
    pub fn value(&self, now: std::time::Instant) -> f32 { self.value_at(self.t(now)) }
    fn value_at(&self, t: f32) -> f32 {
        let dur = self.total - self.last_retarget; let tt = t - self.last_retarget;
        if dur <= 0.0 || tt >= dur { return self.target; } if tt <= 0.0 { return self.init; }
        self.init + (self.target - self.init) * self.ease(tt / dur)
    }
    fn velocity(&self, t: f32) -> f32 { let dur = self.total - self.last_retarget; if dur <= 0.0 { return 0.0; } self.ease_vel((t - self.last_retarget) / dur) * ((self.target - self.init) / dur) }
    pub fn update_target(&mut self, now: std::time::Instant, add: f32) {
        let t = self.t(now).max(self.last_retarget);
        let new_target = self.target + add;
        let cur = self.value_at(t); let nd = new_target - cur;
        if nd.abs() < 0.01 { self.last_retarget = t; self.total = t; self.target = new_target; return; }
        let old_dur = self.total - self.last_retarget;
        if old_dur <= 0.0 { self.init = cur; self.target = new_target; self.last_retarget = t; self.total = t + Self::seg_duration(nd); return; }
        let vel = self.velocity(t);
        let bound = if vel.abs() < 0.01 { f32::MAX } else { let b = nd / vel * 2.5; if b < 0.0 { f32::MAX } else { b } };
        let nd_dur = Self::seg_duration(nd).min(bound);
        if nd_dur < 0.01 { self.target = new_target; self.total = t; return; }
        let new_slope = vel * (nd_dur / nd);
        self.slope = new_slope.clamp(-1000.0, 1000.0);
        self.init = cur; self.target = new_target; self.total = t + nd_dur; self.last_retarget = t;
    }
}
'''
open('app.rs','w').write(a)
PYEOF
sed -i 's/(build b10)/(build b10)/' app.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A12 | head -40
