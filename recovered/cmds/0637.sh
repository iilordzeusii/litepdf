cd /tmp/scratch/app; sed -i 's/if awaiting \&\& self.perf.sync < 8 {/if awaiting \&\& self.perf.sync_frame < 2 {/' src/app.rs; grep -n 'perf.sync_frame' src/app.rs | head -2; python3 - <<'E'
p='/tmp/scratch/app/src/app.rs'; s=open(p).read()
s=s.replace("pub sync: u32, sync_max: f32,","pub sync: u32, pub sync_frame: u32, sync_max: f32,",1)
s=s.replace("sync: 0, sync_max: 0.0, refresh_ms: 0.0, lines: 0, started: false } }","sync: 0, sync_frame: 0, sync_max: 0.0, refresh_ms: 0.0, lines: 0, started: false } }",1)
s=s.replace("pub fn synced(&mut self, ms: f32) { self.sync += 1;","pub fn synced(&mut self, ms: f32) { self.sync += 1; self.sync_frame += 1;",1)
s=s.replace("        let ms = t0.elapsed().as_secs_f32() * 1000.0;\n        if let Some(l) = self.last_start","        self.sync_frame = 0;\n        let ms = t0.elapsed().as_secs_f32() * 1000.0;\n        if let Some(l) = self.last_start",1)
open(p,'w').write(s)
E
grep -n 'b3' /tmp/scratch/litepdf.nsi | head; source /tmp/scratch/wenv.sh; timeout 110 cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E '^error' -A12 | head -30; ls -la target/x86_64-pc-windows-gnu/release/*.exe
