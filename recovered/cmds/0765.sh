cd /tmp/scratch/app/src; grep -n 'LineDelta' -A3 ~/.cargo/registry/src/*/egui-winit-0.34.3/src/lib.rs | head -8; python3 - <<'EOF'
s=open('app.rs').read()
s=s.replace("notch_in += v * 100.0 * self.diag.tp_gain;","notch_in += v * sys_lines() * (100.0 / 3.0) * self.diag.tp_gain;")
s=s.replace("tp_px += v * 100.0 * self.diag.tp_gain;","tp_px += v * sys_lines() * (100.0 / 3.0) * self.diag.tp_gain;")
s=s.replace("pub fn zoom_step(","""/// Lines per wheel tick from Windows (SPI_GETWHEELSCROLLLINES), as Chromium's web_input_event_builders_win.cc reads it; default 3.
pub fn sys_lines() -> f32 {
    #[cfg(windows)]
    { extern "system" { fn SystemParametersInfoW(a: u32, b: u32, c: *mut std::ffi::c_void, d: u32) -> i32; }
      let mut n: u32 = 3; let ok = unsafe { SystemParametersInfoW(0x0068, 0, &mut n as *mut u32 as *mut _, 0) };
      if ok != 0 && n > 0 && n < 100 { return n as f32; } }
    3.0
}
pub fn zoom_step(""",1)
open('app.rs','w').write(s)
EOF
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error|Finished' -A8
