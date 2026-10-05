#[path = "../ops.rs"] mod ops;
#[path = "../extras.rs"] mod extras;
#[path = "../ocr.rs"] mod ocr;
#[path = "../crash.rs"] mod crash;
use mupdf::pdf::PdfDocument;
fn main() {
    crash::install();
    let a: Vec<String> = std::env::args().collect();
    if a.get(1).map(|s| s == "--ocr").unwrap_or(false) { std::process::exit(extras::ocr_child_main(&a[2..])); }
    if a.get(2).map(|s| s == "--links").unwrap_or(false) {
        let d = PdfDocument::open(&a[1]).unwrap();
        for i in 0..d.page_count().unwrap() { for l in d.load_page(i).unwrap().links().unwrap() {
            let dd = l.dest.or_else(|| d.resolve_link(&l.uri).ok().flatten());
            println!("page {} rect {:?} uri {:?} dest {:?}", i + 1, (l.bounds.x0, l.bounds.y0, l.bounds.x1, l.bounds.y1), l.uri, dd.map(|x| (x.loc.page_number, x.kind)));
        } }
        return;
    }
    let mut d = PdfDocument::open(&a[1]).unwrap();
    let n = d.page_count().unwrap() as usize;
    let t = std::time::Instant::now();
    let st = extras::ocr_document(&a[1], &mut d, 0, n - 1, a.get(3).map(|x| x == "force").unwrap_or(false), &mut |m| eprintln!("{m}")).unwrap();
    println!("words={} done={} skipped={} empty={} engine={} time={:?}", st.words, st.done, st.skipped, st.empty, st.engine, t.elapsed());
    if st.words > 0 { ops::save(&d, &a[2], true).unwrap(); }
}
