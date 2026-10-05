cd /tmp/scratch/app/src && cat >> ops.rs <<'EOF'

use mupdf::{Rect, TextPageFlags, Quad};
use mupdf::pdf::PageImageSource;
use mupdf::Image;

/// True redaction: removes the text/images under the boxes from the page content (not an overlay).
pub fn redact_rects(input: &str, rects: &[(usize, Rect)], out: &str) -> Result<(), Error> {
    let mut d = PdfDocument::open(input)?;
    let mut pages: Vec<usize> = rects.iter().map(|r| r.0).collect();
    pages.sort(); pages.dedup();
    for pi in pages {
        let mut p = d.load_pdf_page(pi as i32)?;
        for (_, r) in rects.iter().filter(|r| r.0 == pi) { p.add_redact_annotation(*r)?; }
        p.apply_redactions()?;
        p.update()?;
    }
    save(&d, out, true)
}

/// Find every occurrence of `needle` and redact it.
pub fn redact_text(input: &str, needle: &str, out: &str) -> Result<usize, Error> {
    let doc = mupdf::Document::open(input)?;
    let mut rects = vec![];
    for i in 0..doc.page_count()? {
        let pg = doc.load_page(i)?;
        let tp = pg.to_text_page(TextPageFlags::empty())?;
        for q in tp.search(needle)? { rects.push((i as usize, quad_rect(&q))); }
    }
    let n = rects.len();
    redact_rects(input, &rects, out)?;
    Ok(n)
}

pub fn quad_rect(q: &Quad) -> Rect {
    let xs = [q.ul.x, q.ur.x, q.ll.x, q.lr.x]; let ys = [q.ul.y, q.ur.y, q.ll.y, q.lr.y];
    Rect::new(xs.iter().cloned().fold(f32::MAX, f32::min), ys.iter().cloned().fold(f32::MAX, f32::min), xs.iter().cloned().fold(f32::MIN, f32::max), ys.iter().cloned().fold(f32::MIN, f32::max))
}

/// Downsample large images and re-encode them as JPEG, then garbage-collect and compress streams.
pub fn compress(input: &str, out: &str, max_dim: u32, quality: u8) -> Result<(usize, usize), Error> {
    let mut d = PdfDocument::open(input)?;
    let mut done = std::collections::HashSet::new();
    let (mut replaced, mut seen) = (0, 0);
    for pi in 0..d.page_count()? {
        let mut page = d.load_pdf_page(pi)?;
        for info in page.images()? {
            if !done.insert(info.xref) { continue; }
            seen += 1;
            if info.width.max(info.height) <= max_dim { continue; }
            let Ok(ex) = d.extract_image(info.xref) else { continue };
            let Ok(img) = Image::from_bytes(&ex.encoded) else { continue };
            let Ok(mut pm) = img.to_pixmap() else { continue };
            if pm.alpha() { continue; }
            let mut level = 0; let mut w = pm.width();
            while w > max_dim { w /= 2; level += 1; }
            if level > 0 { if pm.shrink(level).is_err() { continue; } }
            let (w, h, n) = (pm.width() as u16, pm.height() as u16, pm.n());
            let ct = match n { 1 => jpeg_encoder::ColorType::Luma, 3 => jpeg_encoder::ColorType::Rgb, _ => continue };
            let mut buf = vec![];
            if jpeg_encoder::Encoder::new(&mut buf, quality).encode(pm.samples(), w, h, ct).is_err() { continue; }
            if page.replace_image(&mut d, info.xref, PageImageSource::Bytes { data: &buf, format_hint: Some("jpeg") }).is_ok() { replaced += 1; }
        }
    }
    save(&d, out, true)?;
    Ok((replaced, seen))
}
EOF
sed -i 's/^mupdf = "0.8.0"/mupdf = "0.8.0"\njpeg-encoder = "0.6"/' /tmp/scratch/app/Cargo.toml /tmp/scratch/shot/Cargo.toml
cd /tmp/scratch/shot; cat >> src/bin/optest.rs <<'EOF'
#[allow(dead_code)]
fn extra(a: &str) {
    let n = ops::redact_text(a, "SECRET-1234", "/tmp/scratch/o_red.pdf").unwrap();
    println!("redact matches={n}");
    let (r, s) = ops::compress(a, "/tmp/scratch/o_cmp.pdf", 800, 70).unwrap();
    println!("compress images replaced={r}/{s}");
}
EOF
sed -i 's|    println!("decrypt: {}", text("/tmp/scratch/o_dec.pdf"));|    println!("decrypt: {}", text("/tmp/scratch/o_dec.pdf"));\n    extra(\&a);|' src/bin/optest.rs
source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin optest 2>&1 | grep -E "^error|Finished" -A9 | head -40 | cut -c1-180); ./target/release/optest ../t.pdf 2>&1 | tail -3
