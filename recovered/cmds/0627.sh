cd /tmp/scratch/app; grep -c 'render_job_doc(list' src/render.rs; source /tmp/scratch/wenv.sh; timeout 110 cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E '^error' -A9 | head -150
