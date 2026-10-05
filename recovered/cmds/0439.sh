cd /tmp/scratch/app; mkdir -p src/bin; cat > src/bin/ocrcli.rs <<'EOF'
#[path = "../ops.rs"] mod ops;
#[path = "../extras.rs"] mod extras;
#[path = "../ocr.rs"] mod ocr;
use mupdf::pdf::PdfDocument;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let mut d = PdfDocument::open(&a[1]).unwrap();
    let n = d.page_count().unwrap() as usize;
    let t = std::time::Instant::now();
    let st = extras::ocr_document(&mut d, 0, n - 1, a.get(3).map(|x| x == "force").unwrap_or(false), &mut |m| eprintln!("{m}")).unwrap();
    println!("words={} done={} skipped={} empty={} engine={} time={:?}", st.words, st.done, st.skipped, st.empty, st.engine, t.elapsed());
    if st.words > 0 { ops::save(&d, &a[2], true).unwrap(); }
}
EOF
source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu --bin ocrcli 2>&1 | grep -E "^error|Finished" -A6 | head -30
T=/tmp/scratch/wt; rm -rf $T; mkdir -p $T/ocr; cp target/x86_64-pc-windows-gnu/release/ocrcli.exe $T/; cp /tmp/scratch/ocrdl/win/*.dll $T/; cp /tmp/scratch/ocrdl/{det.onnx,rec.onnx,dict.txt} $T/ocr/; ls $T; cat /tmp/scratch/wenv2.sh | head -5
