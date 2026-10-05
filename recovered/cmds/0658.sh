cd /tmp/scratch/app; git log --oneline 2>&1 | head -3; ls /tmp/*.b4 /tmp/app.rs* 2>&1; sed -n 546,556p src/app.rs | cut -c1-160; sed -n 421,440p src/app.rs | cut -c1-160
