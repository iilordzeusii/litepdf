cd /tmp/scratch/app; source /tmp/scratch/wenv.sh; timeout 100 cargo build --release --target x86_64-pc-windows-gnu 2>&1 | tail -3; ls -la target/x86_64-pc-windows-gnu/release/*.exe
