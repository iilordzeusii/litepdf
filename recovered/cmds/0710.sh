cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a,x[:60]; a=a.replace(x,y,1)
rep("pub struct Diag { pub overlay: bool,","pub struct Diag { pub tp_gain: f32, pub tp_tau: f32, pub z_gain: f32, pub z_tau: f32, pub overlay: bool,")
rep("Diag { overlay: false,","Diag { tp_gain: 22.0, tp_tau: 30.0, z_gain: 1.0, z_tau: 35.0, overlay: false,")
rep("pub zanim: Option<(f32, f32, std::time::Instant)>,","pub zanim: Option<(f32, f32, std::time::Instant)>, pub zrem: f32,")
rep("zanim: None,","zanim: None, zrem: 0.0,")
# zoom: all ctrl+wheel into zn (log units), scaled by gain
rep("if is_notch(delta.y) { zn += pts / 200.0; } else { z *= (pts / 200.0).exp(); }","zn += pts / 200.0;")
i=a.index("            let zd = { let now = std::time::Instant::now();"); j=a.index("zd0 * rel.exp() };",i)+len("zd0 * rel.exp() };")
a=a[:i]+"""            let zd = {
                let dt = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);
                self.zrem += zn * self.diag.z_gain;
                let mut rel = 0.0f32;
                if self.zrem != 0.0 { rel = if self.zrem.abs() < 0.0005 { self.zrem } else { self.zrem * (1.0 - (-dt / (self.diag.z_tau / 1000.0)).exp()) }; self.zrem -= rel; if self.zrem != 0.0 { ctx.request_repaint(); } }
                zd0 * rel.exp() };"""+a[j:]
# touchpad scroll
rep("else { req += delta.y * 40.0; }","else { req += delta.y * self.diag.tp_gain; }")
rep("            let raw_total = req + notch_in;\n            let sd = req + rel;","""            let raw_total = req + notch_in;
            // touchpad: instant-start exponential follow (moves a share of the remaining distance on the very first frame)
            let dt = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);
            self.notch += req;
            let mut tp = 0.0f32;
            if self.notch != 0.0 { tp = if self.notch.abs() < 0.3 { self.notch } else { self.notch * (1.0 - (-dt / (self.diag.tp_tau / 1000.0)).exp()) }; self.notch -= tp; if self.notch != 0.0 { ctx.request_repaint(); } }
            let sd = tp + rel;""")
rep('            ui.checkbox(&mut self.diag.overlay,','''            ui.add(egui::Slider::new(&mut self.diag.tp_gain, 8.0..=60.0).text("Touchpad scroll speed"));
            ui.add(egui::Slider::new(&mut self.diag.tp_tau, 1.0..=120.0).text("Touchpad smoothing (ms)"));
            ui.add(egui::Slider::new(&mut self.diag.z_gain, 0.3..=3.0).text("Zoom speed"));
            ui.add(egui::Slider::new(&mut self.diag.z_tau, 1.0..=120.0).text("Zoom smoothing (ms)"));
            ui.checkbox(&mut self.diag.overlay,''')
open('app.rs','w').write(a)
PYEOF
grep -n 'req += delta.y \* area\|let mut req' app.rs | head -3
sed -i 's/(build b9)/(build b10)/; s/perf log (build b9)/perf log (build b10)/' app.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head -30
