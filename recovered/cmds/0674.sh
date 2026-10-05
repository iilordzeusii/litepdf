cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y,n=1):
    global a
    assert x in a,x[:60]; a=a.replace(x,y) if n==0 else a.replace(x,y,n)
rep("std::time::Instant::now() + std::time::Duration::from_millis(250)","std::time::Instant::now()",0)
rep("if std::time::Instant::now() < due || ctx.input(|i| i.pointer.any_down()) { ctx.request_repaint_after(std::time::Duration::from_millis(120)); return; }","if std::time::Instant::now() < due || ctx.input(|i| i.pointer.any_down()) { ctx.request_repaint(); return; }")
rep("let settled = self.zoom_t.elapsed() > std::time::Duration::from_millis(140);\n            if !settled { ctx.request_repaint_after(std::time::Duration::from_millis(150)); }","let settled = true;")
i=a.index("            if self.notch != 0.0 { let dt"); j=a.index("\n",i)
a=a[:i]+"            if self.notch != 0.0 { rel = self.notch; self.notch = 0.0; }"+a[j:]
rep("let sd = if self.diag.raw_wheel { req + rel } else if over { ui.input(|i| i.smooth_scroll_delta.y) } else { 0.0 };","let sd = req + rel;")
rep('            ui.checkbox(&mut self.diag.raw_wheel, "Raw touchpad/wheel (off = egui eased scroll)");\n','')
rep('if self.diag.raw_wheel { "raw" } else { "egui-eased" }','"raw"')
open('app.rs','w').write(a)
m=open('main.rs').read()
m=m.replace("        let mut app = app;","        cc.egui_ctx.style_mut(|s| { s.animation_time = 0.0; s.interaction.tooltip_delay = 0.0; s.interaction.show_tooltips_only_when_still = false; s.scroll_animation = egui::style::ScrollAnimation::none(); });\n        let mut app = app;")
open('main.rs','w').write(m)
PYEOF
sed -i 's/(build b5)/(build b6)/; s/perf log (build b5)/perf log (build b6)/' app.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head -30
