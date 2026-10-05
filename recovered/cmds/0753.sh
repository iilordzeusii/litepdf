cd /tmp/scratch/app/src; python3 - <<'EOF'
s=open('app.rs').read()
# separate wheel zoom (discrete steps) from pinch/multitouch (continuous)
s=s.replace("ui.input(|i| { let mut z = 1.0f32; let mut zn = 0.0f32;","ui.input(|i| { let mut z = 1.0f32; let mut zn = 0.0f32; let mut zw = 0.0f32;")
s=s.replace("z *= (px / 100.0).exp().clamp(0.75, 1.25); }","zw += (px / 100.0).exp().clamp(0.75, 1.25).ln(); }")
s=s.replace("(z, zn) }) };","(z, zw) }) };")
s=s.replace("let _ = zn; let zd = zd0; // Chromium applies each ctrl-wheel / pinch step directly, no easing",
"""self.zrem += zn; // ctrl+wheel steps (Windows delivers a touchpad pinch this way) go to a log-space remainder that is eased out from the first frame
            let zd = { let dt = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05); let tau = self.diag.z_tau / 1000.0; let take = if self.zrem.abs() < 1e-4 { self.zrem } else { self.zrem * (1.0 - (-dt / tau).exp()) }; self.zrem -= take; if self.zrem != 0.0 { ctx.request_repaint(); } zd0 * take.exp() };""")
open('app.rs','w').write(s)
EOF
grep -n 'zw += \|self.zrem += ' app.rs | cut -c1-80
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error|Finished' -A8
