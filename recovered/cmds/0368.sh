cd /tmp/scratch/shot; cat > src/bin/bmptest.rs <<'EOF'
#[path = "/tmp/scratch/app/src/extras.rs"]
#[allow(dead_code)]
mod extras;
#[path = "/tmp/scratch/app/src/ops.rs"]
#[allow(dead_code)]
mod ops;
use mupdf::{Colorspace, Matrix};
fn main(){
    let d = mupdf::Document::open("/tmp/scratch/tess/scan_raw.pdf").unwrap();
    let pg = d.load_page(0).unwrap(); let s=300.0/72.0;
    let pm = pg.to_pixmap(&Matrix::new_scale(s,s), &Colorspace::device_rgb(), false, true).unwrap();
    println!("{}x{} n={} stride={} samples={}", pm.width(), pm.height(), pm.n(), pm.stride(), pm.samples().len());
    extras::write_bmp(std::path::Path::new("/tmp/scratch/wp/drive_c/app.bmp"), pm.width() as usize, pm.height() as usize, pm.samples()).unwrap();
}
EOF
source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 100 cargo build --release --bin bmptest 2>&1 | grep -E "^error" -A8 | head -20; ./target/release/bmptest
source /tmp/scratch/wenv2.sh; export DISPLAY=:77; cd /tmp/scratch/wp/drive_c; timeout 60 $WINE /tmp/scratch/tess/bt/bin/tesseract.exe 'C:\app.bmp' 'C:\appout' --tessdata-dir 'Z:\tmp\scratch\tess\td' -l eng --psm 3 -c tessedit_create_tsv=1 2>&1 | tail -3; wc -l appout.tsv; head -c 300 appout.txt
