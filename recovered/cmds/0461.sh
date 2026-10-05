cd /tmp/scratch/app; python3 - <<'E'
s=open('src/main.rs').read()
s=s.replace('.with_title("LitePDF")','.with_title("LitePDF").with_icon(egui::IconData { rgba: include_bytes!("../icon48.rgba").to_vec(), width: 48, height: 48 })')
open('src/main.rs','w').write(s)
E
grep -n with_icon src/main.rs | head -2; sleep 30; cat /tmp/rc.log; ls -la icon.o 2>&1; pgrep -fa "ziglang|zig" | head -3
