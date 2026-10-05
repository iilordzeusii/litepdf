cd /tmp/scratch/app/src && cat >> ops.rs <<'EOF'

use mupdf::pdf::PdfAnnotationType;
use mupdf::color::AnnotationColor;
use mupdf::Point;

pub fn rgb(c: [f32; 3]) -> AnnotationColor { AnnotationColor::Rgb { red: c[0], green: c[1], blue: c[2] } }

/// kind: 0 highlight, 1 underline, 2 strikeout
pub fn add_markup(doc: &mut PdfDocument, page: i32, kind: u8, quads: Vec<Quad>, color: [f32; 3]) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(page)?;
    let mut a = match kind { 0 => p.add_highlight_annotation(quads)?, 1 => p.add_underline_annotation(quads)?, _ => p.add_strikeout_annotation(quads)? };
    a.set_color(rgb(color))?;
    a.update()?; p.update()?;
    Ok(())
}

pub fn add_ink(doc: &mut PdfDocument, page: i32, strokes: Vec<Vec<(f32, f32)>>, color: [f32; 3], width: f32) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(page)?;
    let st: Vec<Vec<Point>> = strokes.into_iter().map(|s| s.into_iter().map(|(x, y)| Point::new(x, y)).collect()).collect();
    let mut a = p.add_ink_annotation(st)?;
    a.set_color(rgb(color))?;
    a.set_border_width(width)?;
    a.update()?; p.update()?;
    Ok(())
}

pub fn add_freetext(doc: &mut PdfDocument, page: i32, rect: Rect, text: &str, size: f32, color: [f32; 3]) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(page)?;
    let mut a = p.add_free_text_annotation(rect, text)?;
    a.set_default_appearance("Helv", size, Some(rgb(color)))?;
    a.set_border_width(0.0)?;
    a.update()?; p.update()?;
    Ok(())
}

fn seg_dist(p: Point, a: Point, b: Point) -> f32 {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    let l2 = dx * dx + dy * dy;
    let t = if l2 == 0.0 { 0.0 } else { (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0) };
    ((p.x - (a.x + t * dx)).powi(2) + (p.y - (a.y + t * dy)).powi(2)).sqrt()
}

/// Eraser: removes the annotation under the point. Ink is hit by distance to the stroke, others by their box.
pub fn erase_at(doc: &mut PdfDocument, page: i32, pt: Point, tol: f32) -> Result<bool, Error> {
    let mut p = doc.load_pdf_page(page)?;
    let mut target = None;
    for a in p.annotations() {
        let t = a.r#type()?;
        let hit = match t {
            PdfAnnotationType::Ink => {
                let mut h = false;
                for s in a.ink_list()? { for w in s.windows(2) { if seg_dist(pt, w[0], w[1]) <= tol { h = true; } } if s.len() == 1 && seg_dist(pt, s[0], s[0]) <= tol { h = true; } }
                h
            }
            PdfAnnotationType::Widget | PdfAnnotationType::Link | PdfAnnotationType::Popup | PdfAnnotationType::Redact => false,
            _ => { let b = a.bounds()?; pt.x >= b.x0 - tol && pt.x <= b.x1 + tol && pt.y >= b.y0 - tol && pt.y <= b.y1 + tol }
        };
        if hit { target = Some(a); }
    }
    if let Some(a) = target { p.delete_annotation(a)?; p.update()?; return Ok(true); }
    Ok(false)
}

pub fn annot_summary(doc: &PdfDocument, page: i32) -> Result<Vec<String>, Error> {
    let p = doc.load_pdf_page(page)?;
    let mut v = vec![];
    for a in p.annotations() { v.push(format!("{:?}", a.r#type()?)); }
    Ok(v)
}
EOF
cd /tmp/scratch/shot; cat > src/bin/annotest.rs <<'EOF'
#[path = "/tmp/scratch/app/src/ops.rs"]
mod ops;
use mupdf::{pdf::PdfDocument, Point, Rect, TextPageFlags};
fn main() {
    let a = std::env::args().nth(1).unwrap();
    let mut d = PdfDocument::open(&a).unwrap();
    println!("before: {:?}", ops::annot_summary(&d, 1).unwrap());
    // highlight "Another line" on page 2 from text search
    let doc2 = mupdf::Document::open(&a).unwrap();
    let tp = doc2.load_page(1).unwrap().to_text_page(TextPageFlags::empty()).unwrap();
    let q = tp.search("Another line").unwrap();
    ops::add_markup(&mut d, 1, 0, q.clone(), [1.0, 0.9, 0.0]).unwrap();
    ops::add_markup(&mut d, 1, 1, q.clone(), [0.0, 0.5, 1.0]).unwrap();
    ops::add_markup(&mut d, 1, 2, q, [1.0, 0.0, 0.0]).unwrap();
    ops::add_ink(&mut d, 1, vec![vec![(100.0, 200.0), (150.0, 230.0), (200.0, 200.0), (250.0, 240.0)]], [0.0, 0.2, 0.9], 3.0).unwrap();
    ops::add_freetext(&mut d, 1, Rect::new(100.0, 300.0, 300.0, 330.0), "Hello FreeText", 14.0, [0.1, 0.1, 0.1]).unwrap();
    println!("after add: {:?}", ops::annot_summary(&d, 1).unwrap());
    println!("erase ink on stroke: {}", ops::erase_at(&mut d, 1, Point::new(150.0, 230.0), 4.0).unwrap());
    println!("erase miss: {}", ops::erase_at(&mut d, 1, Point::new(500.0, 700.0), 4.0).unwrap());
    println!("after erase: {:?}", ops::annot_summary(&d, 1).unwrap());
    ops::save(&d, "/tmp/scratch/o_annot.pdf", false).unwrap();
}
EOF
source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin annotest 2>&1 | grep -E "^error" -A9 | head -40 | cut -c1-170); ./target/release/annotest ../t.pdf 2>&1 | tail -8
