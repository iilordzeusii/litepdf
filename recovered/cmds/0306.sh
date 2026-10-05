cd /tmp/scratch/app/src && cat >> ops.rs <<'EOF'

pub struct OcrWord { pub text: String, pub x: f32, pub y: f32, pub w: f32, pub h: f32 } // pixels, top-left origin

/// Adds an invisible (render mode 3) text layer on the ORIGINAL page. Page size, content and look are unchanged.
pub fn add_text_layer(doc: &mut PdfDocument, page_idx: i32, words: &[OcrWord], dpi: f32) -> Result<(), Error> {
    let mut page = doc.load_pdf_page(page_idx)?;
    let b = page.bounds()?;
    let (fname, _, _) = page.insert_font(doc, &mupdf::pdf::InsertFontOptions::new("Helv"))?;
    let s = 72.0 / dpi;
    let mut c = String::from("q\n");
    for w in words {
        let t: String = w.text.chars().filter(|ch| (*ch as u32) >= 32 && (*ch as u32) < 256).collect();
        if t.is_empty() { continue; }
        let size = (w.h * s * 0.85).max(1.0);
        let approx = t.chars().count() as f32 * 0.5 * size;
        let tz = (100.0 * (w.w * s) / approx).clamp(10.0, 400.0);
        let x = b.x0 + w.x * s;
        let y = b.y1 - (w.y + w.h * 0.8) * s;
        let esc: String = t.chars().flat_map(|ch| match ch { '(' | ')' | '\\' => vec!['\\', ch], _ => vec![ch] }).collect();
        c.push_str(&format!("BT 3 Tr /{fname} {size:.2} Tf {tz:.1} Tz 1 0 0 1 {x:.2} {y:.2} Tm ({esc}) Tj ET\n"));
    }
    c.push_str("Q\n");
    let bytes: Vec<u8> = c.chars().map(|ch| ch as u32 as u8).collect();
    page.insert_contents(doc, &bytes, true)?;
    Ok(())
}
EOF
cd /tmp/scratch/shot; cat > src/bin/ocrtest.rs <<'EOF'
#[path = "/tmp/scratch/app/src/ops.rs"]
mod ops;
use mupdf::pdf::PdfDocument;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let (inp, tsv, out, dpi) = (&a[1], &a[2], &a[3], a[4].parse::<f32>().unwrap());
    let mut words = vec![];
    for l in std::fs::read_to_string(tsv).unwrap().lines().skip(1) {
        let f: Vec<&str> = l.split('\t').collect();
        if f.len() < 12 || f[0] != "5" { continue; }
        let t = f[11].trim(); if t.is_empty() { continue; }
        words.push(ops::OcrWord { text: t.to_string(), x: f[6].parse().unwrap(), y: f[7].parse().unwrap(), w: f[8].parse().unwrap(), h: f[9].parse().unwrap() });
    }
    let mut d = PdfDocument::open(inp).unwrap();
    ops::add_text_layer(&mut d, 0, &words, dpi).unwrap();
    ops::save(&d, out, true).unwrap();
    println!("words={}", words.len());
}
EOF
source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin ocrtest 2>&1 | grep -E "^error" -A9 | head -30 | cut -c1-170)
