cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a,x[:60]; a=a.replace(x,y,1)
rep("pub notch: f32,","pub notch: f32, pub sanim: Option<(f32, f32, std::time::Instant)>, pub zanim: Option<(f32, f32, std::time::Instant)>,")
rep("notch: 0.0,","notch: 0.0, sanim: None, zanim: None,")
# zoom block
rep("let zd = { let hov","let (zd0, zn) = { let hov")
rep("let hh = area.height();\n                ui.input(|i| { let mut z = 1.0f32;","let hh = area.height();\n                ui.input(|i| { let mut z = 1.0f32; let mut zn = 0.0f32;")
rep("                            z *= (pts / 200.0).exp();","                            if is_notch(delta.y) { zn += pts / 200.0; } else { z *= (pts / 200.0).exp(); }")
rep("                    z }) };","                    (z, zn) }) };\n            let zd = { let now = std::time::Instant::now();\n                if zn != 0.0 { let rem = self.zanim.map_or(0.0, |(t, ap, _)| t - ap); self.zanim = Some((rem + zn, 0.0, now)); }\n                let mut rel = 0.0f32;\n                if let Some((t, ap, t0)) = self.zanim { let p = now.duration_since(t0).as_secs_f32() / 0.15; let tgt = t * cubic_ease(p); rel = tgt - ap; self.zanim = if p >= 1.0 { None } else { ctx.request_repaint(); Some((t, tgt, t0)) }; }\n                zd0 * rel.exp() };")
# scroll
rep("if delta.y.abs() >= 0.5 { notch_in += delta.y * 90.0; } else { req += delta.y * 40.0; }","if is_notch(delta.y) { notch_in += delta.y * 100.0; } else { req += delta.y * 40.0; }")
rep("            if notch_in != 0.0 { self.notch += notch_in; }\n            let mut rel = 0.0f32;\n            if self.notch != 0.0 { rel = self.notch; self.notch = 0.0; }",
"""            let mut rel = 0.0f32;
            { let now = std::time::Instant::now();
              if notch_in != 0.0 { let rem = self.sanim.map_or(0.0, |(t, ap, _)| t - ap); self.sanim = Some((rem + notch_in, 0.0, now)); }
              if let Some((t, ap, t0)) = self.sanim { let p = now.duration_since(t0).as_secs_f32() / 0.15; let tgt = t * cubic_ease(p); rel = tgt - ap; self.sanim = if p >= 1.0 { None } else { ctx.request_repaint(); Some((t, tgt, t0)) }; } }""")
a+='''
/// A wheel notch arrives as a whole number of lines; a touchpad sends fractions.
pub fn is_notch(d: f32) -> bool { d.abs() >= 0.99 && (d.abs() - d.abs().round()).abs() < 0.02 }
/// Chromium's ease-in-out timing function, cubic-bezier(0.42, 0, 0.58, 1): progress p (0..1) to eased fraction.
pub fn cubic_ease(p: f32) -> f32 {
    if p <= 0.0 { return 0.0; } if p >= 1.0 { return 1.0; }
    let bx = |t: f32| 3.0 * (1.0 - t) * (1.0 - t) * t * 0.42 + 3.0 * (1.0 - t) * t * t * 0.58 + t * t * t;
    let by = |t: f32| 3.0 * (1.0 - t) * t * t + t * t * t;
    let (mut lo, mut hi) = (0.0f32, 1.0f32);
    for _ in 0..24 { let m = (lo + hi) / 2.0; if bx(m) < p { lo = m; } else { hi = m; } }
    by((lo + hi) / 2.0)
}
'''
open('app.rs','w').write(a)
PYEOF
sed -i 's/(build b8)/(build b9)/; s/perf log (build b8)/perf log (build b9)/' app.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head -30
