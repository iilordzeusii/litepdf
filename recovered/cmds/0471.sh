cd /tmp/scratch/app; cat > src/bin/compcli.rs <<'EOF'
#[path = "../ops.rs"] mod ops;
fn main() { let a: Vec<String> = std::env::args().collect(); let r = ops::compress(&a[1], &a[2], a[3].parse().unwrap(), a[4].parse().unwrap()).unwrap(); println!("replaced {} of {}", r.0, r.1); }
EOF
python3 - <<'E'
from PIL import Image, ImageFilter
import numpy as np
rng=np.random.default_rng(1)
a=(rng.random((3300,2550,3))*255).astype('uint8')
im=Image.fromarray(a).filter(ImageFilter.GaussianBlur(1.2))
im.save('/tmp/scratch/wt/scan.pdf',quality=92,resolution=300)
im.convert('L').save('/tmp/scratch/wt/scang.pdf',quality=92,resolution=300)
E
source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu --bin compcli 2>&1 | grep -E "^error|Finished" -A8; cp target/x86_64-pc-windows-gnu/release/compcli.exe /tmp/scratch/wt/
source /tmp/scratch/wenv2.sh; export DISPLAY=:77; cd /tmp/scratch/wt; for f in scan scang; do for dpi in 150 100; do timeout 60 $WINE compcli.exe $f.pdf ${f}_$dpi.pdf $((dpi*117/10)) 70 2>&1 | grep -v fixme | tail -1; done; done; ls -la scan*.pdf
