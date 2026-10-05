source ~/.cargo/env; cd /tmp/scratch/sg; (timeout 110 cargo build --release 2>&1 | grep -E "^error|Finished" -A8 | head -20 | cut -c1-180)
