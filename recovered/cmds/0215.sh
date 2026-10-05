sleep 115; grep -E "^error|Finished" -A8 /tmp/scratch/a1.log | head -20 | cut -c1-200; ls -la /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/litepdf.exe 2>&1
