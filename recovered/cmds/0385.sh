cd /tmp/scratch/shot; cat > src/bin/ftedit.rs <<'EOF'
#[path = "/tmp/scratch/app/src/ops.rs"]
#[allow(dead_code)]
mod ops;
use mupdf::{pdf::PdfDocument, Point, Rect};
fn main(){
    let mut d = PdfDocument::open("/tmp/scratch/t.pdf").unwrap();
    ops::add_freetext_f(&mut d, 1, Rect::new(100.0,300.0,260.0,330.0), "Hello draft", 0, 12.0, [0.0;3]).unwrap();
    let f = ops::freetext_at(&d, 1, Point::new(120.0,310.0)).unwrap();
    println!("found {:?}", f);
    ops::freetext_update(&mut d, 1, f.idx, Rect::new(100.0,300.0,300.0,340.0), "Edited text\nsecond line", 1, 20.0, [0.8,0.0,0.0]).unwrap();
    let g = ops::freetext_at(&d, 1, Point::new(120.0,310.0)).unwrap();
    println!("after {:?}", g);
    ops::save(&d, "/tmp/o_ft.pdf", false).unwrap();
    ops::freetext_update(&mut d, 1, g.idx, g.rect, "", 0, 12.0, [0.0;3]).unwrap();
    println!("after delete {:?}", ops::freetext_at(&d, 1, Point::new(120.0,310.0)).is_some());
}
EOF
source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 100 cargo build --release --bin ftedit 2>&1 | grep -E "^error" -A8; ./target/release/ftedit; pdftoppm -r 70 -f 2 -l 2 -png /tmp/o_ft.pdf /tmp/ft; mv /tmp/ft-2.png /downloads/ft.png
