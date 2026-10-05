cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
x="let zd = ui.input(|i| i.zoom_delta());"
assert x in a
a=a.replace(x,"""// raw zoom: pinch gesture events and ctrl+wheel (a Windows touchpad pinch arrives as ctrl+wheel); egui's own zoom_delta smooths ctrl+wheel
            let zd = { let hov = ui.input(|i| i.pointer.hover_pos()).map_or(false, |p| area.contains(p)); let hh = area.height();
                ui.input(|i| { let mut z = 1.0f32;
                    for e in &i.events { match e {
                        egui::Event::Zoom(f) => { if hov { z *= *f; } }
                        egui::Event::MouseWheel { unit, delta, modifiers, .. } if hov && (modifiers.command || modifiers.ctrl) => {
                            let pts = match unit { egui::MouseWheelUnit::Line => (delta.x + delta.y) * 40.0, egui::MouseWheelUnit::Page => (delta.x + delta.y) * hh, egui::MouseWheelUnit::Point => delta.x + delta.y };
                            z *= (pts / 200.0).exp();
                        }
                        _ => {} } }
                    if let Some(t) = i.multi_touch() { if hov { z *= t.zoom_delta; } }
                    z }) };""",1)
open('app.rs','w').write(a)
m=open('main.rs').read()
m=m.replace("        cc.egui_ctx.style_mut(|s| { s.animation_time = 0.0; s.interaction.tooltip_delay = 0.0; s.interaction.show_tooltips_only_when_still = false; s.scroll_animation = egui::style::ScrollAnimation::none(); });\n","")
m=m.replace('let vsync = !argv.iter().any(|s| s == "--vsync=off");','let vsync = argv.iter().any(|s| s == "--vsync=on");')
open('main.rs','w').write(m)
PYEOF
grep -n 'vsync' main.rs | head -3; sed -i 's/Restart with --vsync=off to test without vsync./Vsync is off by default (lowest latency, may tear). Launch with --vsync=on to compare./' app.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head -30
