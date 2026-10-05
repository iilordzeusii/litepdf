cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a,x[:60]; a=a.replace(x,y,1)
rep("        self.perf.frame(t0, self.view.bytes, self.view.tile_count(), self.last_sent.len());",
"""        let act = self.perf.active || ctx.input(|i| i.pointer.delta() != egui::Vec2::ZERO || !i.events.is_empty() || i.pointer.any_down());
        if act { self.perf.last_act = t0; }
        self.perf.frame(t0, self.view.bytes, self.view.tile_count(), self.last_sent.len());
        // draw every display refresh while anything is happening, plus a short tail; never wait on a timer
        if self.perf.last_act.elapsed().as_millis() < 500 { ctx.request_repaint(); }""")
rep("pub hits: u32, pub misses: u32,","pub last_act: std::time::Instant, pub gapn: u32, pub hits: u32, pub misses: u32,")
rep("hits: 0, misses: 0, wlines: 0,","last_act: n, gapn: 0, hits: 0, misses: 0, wlines: 0,")
rep("if self.prev_active && self.active && gap < 2000.0 { self.gaps.push(gap); }","if self.prev_active && self.active && gap < 2000.0 { self.gaps.push(gap); if gap > 40.0 && self.gapn < 300 { self.gapn += 1; self.note(format!(\"GAP {gap:.0} ms between frames while active (previous frame's own cost {:.1} ms)\", self.max_ms)); } }")
open('app.rs','w').write(a)
m=open('main.rs').read()
m=m.replace('let vsync = argv.iter().any(|s| s == "--vsync=on");','let vsync = !argv.iter().any(|s| s == "--vsync=off");')
open('main.rs','w').write(m)
PYEOF
sed -i 's/(build b6)/(build b7)/; s/perf log (build b6)/perf log (build b7)/; s/Vsync is off by default (lowest latency, may tear). Launch with --vsync=on to compare./Vsync is on by default. Launch with --vsync=off to compare./' app.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head -20
