cd /tmp/scratch/app; source ~/.cargo/env; source /tmp/scratch/wenv.sh; timeout 100 cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E "^error|Finished" -A7 | head -30 | cut -c1-180
