cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a,x[:60]; a=a.replace(x,y,1)
i=a.index("            { let now = std::time::Instant::now();\n              if notch_in != 0.0"); j=a.index("self.sanim = if p >= 1.0 { None } else { ctx.request_repaint(); Some((t, tgt, t0)) }; } }",i)+len("self.sanim = if p >= 1.0 { None } else { ctx.request_repaint(); Some((t, tgt, t0)) }; } }")
a=a[:i]+"""            { let dtm = ui.input(|i| i.unstable_dt).clamp(0.001, 0.05);
              self.mrem += notch_in;
              if self.mrem != 0.0 { rel = if self.mrem.abs() < 0.3 { self.mrem } else { self.mrem * (1.0 - (-dtm / 0.055f32).exp()) }; self.mrem -= rel; if self.mrem != 0.0 { ctx.request_repaint(); } } }"""+a[j:]
rep("pub zrem: f32,","pub zrem: f32, pub mrem: f32,")
rep("zrem: 0.0,","zrem: 0.0, mrem: 0.0,")
a=a.replace("tp_tau: 30.0","tp_tau: 35.0")
open('app.rs','w').write(a)
PYEOF
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^(error|warning: unused)' -A8 | head -30
