cd /tmp/scratch/app/src; sed -i '752a\            ui.checkbox(\&mut self.diag.rec, "Record input events to input.log (wheel, pinch, touch + resulting zoom/scroll per frame)");' app.rs; sed -n 753p app.rs | cut -c1-150
cat > /tmp/zt.rs <<'EOF'
pub fn zoom_step(cur: f32, target: f32, dt: f32) -> f32 {
    let d = (target / cur).ln(); if d.abs() < 1e-4 { return target; }
    let cap = 3.5 * dt; let step = (d * (1.0 - (-dt / 0.05).exp())).clamp(-cap, cap); cur * step.exp()
}
fn run(hz: f32, name: &str, events: &[(f32, f32)]) {
    let dt = 1.0 / hz; let mut z = 1.66f32; let mut t = 1.66f32; let mut maxch = 0.0f32; let mut first = None; let mut frames_moving = 0; let mut tm = 0.0f32; let mut ei = 0;
    while tm < 1.5 { while ei < events.len() && events[ei].0 <= tm { t = (t * events[ei].1).clamp(0.1, 8.0); ei += 1; if first.is_none() { first = Some(tm); } }
        let nz = zoom_step(z, t, dt); let ch = (nz / z - 1.0).abs(); if ch > 0.0 { frames_moving += 1; } maxch = maxch.max(ch); z = nz; tm += dt; }
    println!("{name} @{hz}Hz: max per-frame change {:.2}%, frames moving {}, final {:.3} target {:.3}", maxch * 100.0, frames_moving, z, t);
}
fn main() {
    for hz in [60.0, 144.0] {
        run(hz, "single x1.25 step (166->207)", &[(0.0, 1.25)]);
        run(hz, "pinch: x1.25 every 50ms for 0.5s", &(0..10).map(|i| (i as f32 * 0.05, 1.25)).collect::<Vec<_>>());
        run(hz, "pinch: x1.05 every 8ms for 0.4s", &(0..50).map(|i| (i as f32 * 0.008, 1.05)).collect::<Vec<_>>());
    }
    // first frame
    let z = zoom_step(1.66, 1.66 * 1.25, 1.0 / 144.0); println!("first frame @144Hz: 1.66 -> {:.4} ({:.2}%)", z, (z / 1.66 - 1.0) * 100.0);
}
EOF
cd /tmp && rustc -O zt.rs -o zt 2>&1 | head -3 && ./zt
