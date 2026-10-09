//! Format conversion: PDF to images / text / Word / HTML, and images to PDF. Runs on its own thread with its own copy of the document handle.
use mupdf::pdf::PdfDocument;
use mupdf::{Colorspace, Document, DocumentWriter, Matrix};
use std::path::Path;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum To { Png, Jpeg, Text, Docx, Html }
impl To {
    pub fn label(self) -> &'static str { match self { To::Png => "PNG images (one per page)", To::Jpeg => "JPEG images (one per page)", To::Text => "Plain text (.txt)", To::Docx => "Word document (.docx)", To::Html => "Web page (.html)" } }
    pub fn ext(self) -> &'static str { match self { To::Png => "png", To::Jpeg => "jpg", To::Text => "txt", To::Docx => "docx", To::Html => "html" } }
}

/// Converts `src` (a PDF on disk) into `out` (a file, or for image formats a folder). Returns a short status line.
pub fn pdf_to(src: &str, out: &Path, to: To, dpi: f32, progress: &dyn Fn(usize, usize)) -> Result<String, String> {
    let doc = PdfDocument::open(src).map_err(|e| e.to_string())?;
    let n = doc.page_count().map_err(|e| e.to_string())?.max(0) as usize;
    match to {
        To::Png | To::Jpeg => {
            std::fs::create_dir_all(out).map_err(|e| e.to_string())?;
            let stem = Path::new(src).file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "page".into());
            let sc = dpi / 72.0;
            for i in 0..n {
                let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
                let pm = pg.to_pixmap(&Matrix::new_scale(sc, sc), &Colorspace::device_rgb(), false, true).map_err(|e| e.to_string())?;
                let f = out.join(format!("{stem}-{:04}.{}", i + 1, to.ext()));
                if to == To::Png { pm.save_as(&f.to_string_lossy(), mupdf::pixmap::ImageFormat::PNG).map_err(|e| e.to_string())?; }
                else {
                    let (w, h, nc) = (pm.width() as usize, pm.height() as usize, pm.n() as usize);
                    let st = pm.stride() as usize; let s = pm.samples();
                    let mut rgb = Vec::with_capacity(w * h * 3);
                    for y in 0..h { for x in 0..w { let o = y * st + x * nc; rgb.extend_from_slice(&s[o..o + 3]); } }
                    let enc = jpeg_encoder::Encoder::new_file(&f, 88).map_err(|e| e.to_string())?;
                    enc.encode(&rgb, w as u16, h as u16, jpeg_encoder::ColorType::Rgb).map_err(|e| e.to_string())?;
                }
                progress(i + 1, n);
            }
            Ok(format!("Saved {n} {} files to {}", to.ext().to_uppercase(), out.display()))
        }
        To::Text => {
            let mut all = String::new();
            for i in 0..n {
                let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
                if let Ok(tp) = pg.to_text_page(mupdf::TextPageFlags::PRESERVE_WHITESPACE) { if let Ok(t) = tp.to_text() { all.push_str(&t); } }
                all.push('\n'); all.push('\u{c}'); all.push('\n');
                progress(i + 1, n);
            }
            std::fs::write(out, all).map_err(|e| e.to_string())?;
            Ok(format!("Saved text to {}", out.display()))
        }
        To::Docx | To::Html => {
            let fmt = if to == To::Docx { "docx" } else { "html" };
            let mut w = DocumentWriter::new(out.to_string_lossy().as_ref(), fmt, "").map_err(|e| e.to_string())?;
            for i in 0..n {
                let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
                let b = pg.bounds().map_err(|e| e.to_string())?;
                let dev = w.begin_page(b).map_err(|e| e.to_string())?;
                pg.run(&dev, &Matrix::IDENTITY).map_err(|e| e.to_string())?;
                w.end_page(dev).map_err(|e| e.to_string())?;
                progress(i + 1, n);
            }
            drop(w);
            Ok(format!("Saved {} to {}. Layout is text-first, so complex pages may reflow.", fmt.to_uppercase(), out.display()))
        }
    }
}

/// Converts one image file (PNG, JPEG, BMP, TIFF, GIF...) into a one-page PDF.
pub fn image_to_pdf(src: &str, out: &Path) -> Result<(), String> {
    let d = Document::open(src).map_err(|e| e.to_string())?;
    let n = d.page_count().map_err(|e| e.to_string())?;
    let mut p = d.convert_to_pdf(0, n - 1, 0).map_err(|e| e.to_string())?;
    p.save(&out.to_string_lossy()).map_err(|e| e.to_string())
}
