cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a,x[:60]; a=a.replace(x,y,1)
rep("pub struct Diag { pub raw_wheel: bool,","pub struct Diag { pub overlay: bool, pub raw_wheel: bool,")
rep("Diag { raw_wheel: true,","Diag { overlay: false, raw_wheel: true,")
rep("pub last_act: std::time::Instant,","pub last_ms: f32, pub last_gap: f32, pub last_act: std::time::Instant,")
rep("last_act: n, gapn: 0,","last_ms: 0.0, last_gap: 0.0, last_act: n, gapn: 0,")
rep("        let ms = t0.elapsed().as_secs_f32() * 1000.0;\n        if let Some(l) = self.last_start { let gap = t0.duration_since(l).as_secs_f32() * 1000.0;","        let ms = t0.elapsed().as_secs_f32() * 1000.0; self.last_ms = ms;\n        if let Some(l) = self.last_start { let gap = t0.duration_since(l).as_secs_f32() * 1000.0; self.last_gap = gap;")
# overlay
rep("        // draw every display refresh while anything is happening","""        if self.diag.overlay {
            let (ms, gap) = (self.perf.last_ms, self.perf.last_gap);
            egui::Area::new(egui::Id::new("perf_overlay")).fixed_pos(pos2(8.0, 64.0)).order(egui::Order::Debug).interactable(false).show(ctx, |ui| {
                egui::Frame::NONE.fill(Color32::from_black_alpha(190)).corner_radius(4.0).inner_margin(6.0).show(ui, |ui| {
                    let col = if gap > 20.0 { Color32::from_rgb(255, 120, 90) } else { Color32::from_rgb(140, 230, 140) };
                    ui.label(egui::RichText::new(format!("frame {ms:.1} ms | gap {gap:.1} ms | {:.0} fps", 1000.0 / gap.max(0.1))).monospace().color(col));
                    ui.label(egui::RichText::new(format!("tiles {} | mem {} MB | queue {}", self.view.tile_count(), self.view.bytes >> 20, self.last_sent.len())).monospace().color(Color32::WHITE));
                });
            });
        }
        // draw every display refresh while anything is happening""")
rep('            ui.checkbox(&mut self.diag.sync_mode,','            ui.checkbox(&mut self.diag.overlay, "Show frame-time overlay");\n            ui.checkbox(&mut self.diag.sync_mode,')
# upload time box
rep("        let mut budget = if fast","        let upl_t = std::time::Instant::now(); let mut upl_n = 0u32;\n        let mut budget = if fast")
rep("            if budget == 0 { more = true; break; }","            if budget == 0 || (upl_n > 0 && upl_t.elapsed().as_secs_f32() > 0.004) { more = true; break; }")
rep("                    budget = budget.saturating_sub(if tile.is_none()","                    upl_n += 1;\n                    budget = budget.saturating_sub(if tile.is_none()")
open('app.rs','w').write(a)
PYEOF
sed -i 's/(build b8)/(build b8)/' app.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head -30
