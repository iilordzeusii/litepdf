grep -E "^error|Finished" -A8 /tmp/scratch/winbuild.log | head -30; pgrep cargo | head -2; ls -la /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/litepdf.exe
