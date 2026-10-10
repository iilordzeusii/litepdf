//! Format conversion: PDF to images / text / Word / HTML, and images to PDF. Runs on its own thread with its own copy of the document handle.
use mupdf::pdf::PdfDocument;
use mupdf::{Colorspace, Document, Matrix};
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
            let mut pages: Vec<Pg> = Vec::with_capacity(n);
            for i in 0..n {
                pages.push(read_page(&doc, i)?);
                progress(i + 1, n);
            }
            let ni: usize = pages.iter().map(|p| p.blocks.iter().filter(|b| matches!(b, Blk::Img { .. })).count()).sum();
            if to == To::Html { std::fs::write(out, html_doc(&pages, src)).map_err(|e| e.to_string())?; }
            else { std::fs::write(out, docx_doc(&pages)).map_err(|e| e.to_string())?; }
            let kind = if to == To::Html { "HTML" } else { "DOCX" };
            Ok(format!("Saved {kind} with {ni} image{} to {}. Text is real and editable; vector drawings (lines, shapes) are not carried over.", if ni == 1 { "" } else { "s" }, out.display()))
        }
    }
}

struct Run { text: String, size: f32, rgb: u32, bold: bool, italic: bool, font: String }
struct Line { x0: f32, y0: f32, y1: f32, runs: Vec<Run> }
enum Blk { Text { x0: f32, y0: f32, y1: f32, lines: Vec<Line> }, Img { x0: f32, y0: f32, x1: f32, y1: f32, mime: &'static str, data: Vec<u8> } }
struct Pg { w: f32, h: f32, blocks: Vec<Blk> }

fn family(name: &str) -> String {
    let n = name.rsplit('+').next().unwrap_or(name);
    let n = n.split(|c| c == '-' || c == ',').next().unwrap_or(n).trim();
    let mut o = String::new(); let mut prev_lower = false;
    for c in n.chars() { if c.is_uppercase() && prev_lower { o.push(' '); } prev_lower = c.is_lowercase(); o.push(c); }
    if o.is_empty() { "Arial".into() } else { o }
}

fn read_page(doc: &PdfDocument, i: usize) -> Result<Pg, String> {
    let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
    let b = pg.bounds().map_err(|e| e.to_string())?;
    let tp = pg.to_text_page(mupdf::TextPageFlags::PRESERVE_IMAGES | mupdf::TextPageFlags::PRESERVE_WHITESPACE).map_err(|e| e.to_string())?;
    let mut blocks = vec![];
    let mut page_rgb: Option<(Vec<u8>, usize, usize)> = None;
    for blk in tp.blocks() {
        let bb = blk.bounds();
        match blk.r#type() {
            mupdf::text_page::TextBlockType::Text => {
                let mut lines = vec![];
                for l in blk.lines() {
                    let lb = l.bounds(); let mut runs: Vec<Run> = vec![];
                    for c in l.chars() {
                        let Some(ch) = c.char() else { continue };
                        let (font, it) = c.font().map(|f| (f.name().to_string(), f.is_italic())).unwrap_or_default();
                        let bold = c.flags().contains(mupdf::text_page::TextCharFlags::BOLD) || font.to_ascii_lowercase().contains("bold");
                        let it = it || font.to_ascii_lowercase().contains("italic") || font.to_ascii_lowercase().contains("oblique");
                        let (size, rgb) = ((c.size() * 2.0).round() / 2.0, c.argb() & 0xFF_FFFF);
                        match runs.last_mut() { Some(r) if r.size == size && r.rgb == rgb && r.bold == bold && r.italic == it && r.font == font => r.text.push(ch), _ => runs.push(Run { text: ch.to_string(), size, rgb, bold, italic: it, font }) }
                    }
                    if !runs.is_empty() { lines.push(Line { x0: lb.x0 - b.x0, y0: lb.y0 - b.y0, y1: lb.y1 - b.y0, runs }); }
                }
                if !lines.is_empty() { blocks.push(Blk::Text { x0: bb.x0 - b.x0, y0: bb.y0 - b.y0, y1: bb.y1 - b.y0, lines }); }
            }
            mupdf::text_page::TextBlockType::Image => {
                let Some(img) = blk.image() else { continue };
                let mut data: Option<(Vec<u8>, &'static str)> = None;
                if let Ok(pm) = img.to_pixmap() { let mut v = vec![]; if pm.write_to(&mut v, mupdf::pixmap::ImageFormat::PNG).is_ok() && v.len() > 8 { data = Some((v, "image/png")); } }
                if data.is_none() {
                    // unusual colour space (CMYK, etc.): take the pixels from a render of the page instead
                    if page_rgb.is_none() {
                        let sc = 150.0 / 72.0;
                        let pm = pg.to_pixmap(&Matrix::new_scale(sc, sc), &Colorspace::device_rgb(), false, true).map_err(|e| e.to_string())?;
                        let (w, h, nc, st) = (pm.width() as usize, pm.height() as usize, pm.n() as usize, pm.stride() as usize); let sm = pm.samples();
                        let mut rgb = Vec::with_capacity(w * h * 3); for y in 0..h { for x in 0..w { let o = y * st + x * nc; rgb.extend_from_slice(&sm[o..o + 3]); } }
                        page_rgb = Some((rgb, w, h));
                    }
                    let (rgb, w, h) = page_rgb.as_ref().unwrap(); let sc = 150.0 / 72.0;
                    let (cx0, cy0) = (((bb.x0 - b.x0) * sc).max(0.0) as usize, ((bb.y0 - b.y0) * sc).max(0.0) as usize);
                    let (cx1, cy1) = ((((bb.x1 - b.x0) * sc).ceil() as usize).min(*w), (((bb.y1 - b.y0) * sc).ceil() as usize).min(*h));
                    if cx1 > cx0 + 1 && cy1 > cy0 + 1 {
                        let (cw, ch) = (cx1 - cx0, cy1 - cy0); let mut buf = Vec::with_capacity(cw * ch * 3);
                        for y in cy0..cy1 { buf.extend_from_slice(&rgb[(y * w + cx0) * 3..(y * w + cx1) * 3]); }
                        let mut v = vec![];
                        if let Ok(enc) = Ok::<_, ()>(jpeg_encoder::Encoder::new(&mut v, 90)) { if enc.encode(&buf, cw as u16, ch as u16, jpeg_encoder::ColorType::Rgb).is_ok() { data = Some((v, "image/jpeg")); } }
                    }
                }
                if let Some((d, mime)) = data { blocks.push(Blk::Img { x0: bb.x0 - b.x0, y0: bb.y0 - b.y0, x1: bb.x1 - b.x0, y1: bb.y1 - b.y0, mime, data: d }); }
            }
            _ => {}
        }
    }
    Ok(Pg { w: b.x1 - b.x0, h: b.y1 - b.y0, blocks })
}

fn esc(s: &str) -> String { let mut o = String::with_capacity(s.len()); for c in s.chars() { match c { '&' => o.push_str("&amp;"), '<' => o.push_str("&lt;"), '>' => o.push_str("&gt;"), '"' => o.push_str("&quot;"), c if (c as u32) < 32 && c != '\t' && c != '\n' => {} c => o.push(c) } } o }

fn b64(d: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut o = String::with_capacity(d.len() * 4 / 3 + 4);
    for c in d.chunks(3) { let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        o.push(T[(n >> 18) as usize & 63] as char); o.push(T[(n >> 12) as usize & 63] as char);
        o.push(if c.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' }); o.push(if c.len() > 2 { T[n as usize & 63] as char } else { '=' }); }
    o
}

/// One absolutely positioned page per PDF page: real text at the original line positions, pictures inline as data URIs.
fn html_doc(pages: &[Pg], src: &str) -> String {
    let title = Path::new(src).file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
    let mut o = format!("<!doctype html>\n<html><head><meta charset=\"utf-8\"><title>{}</title><style>body{{background:#6b7078;margin:0;padding:16px 0}}.pg{{position:relative;margin:0 auto 16px;background:#fff;overflow:hidden;box-shadow:0 2px 10px rgba(0,0,0,.4)}}.pg>*{{position:absolute;margin:0}}.l{{white-space:pre}}</style></head><body>\n", esc(&title));
    for p in pages {
        o.push_str(&format!("<div class=\"pg\" style=\"width:{:.2}pt;height:{:.2}pt\">\n", p.w, p.h));
        for b in &p.blocks { match b {
            Blk::Img { x0, y0, x1, y1, mime, data } => o.push_str(&format!("<img alt=\"\" style=\"left:{:.2}pt;top:{:.2}pt;width:{:.2}pt;height:{:.2}pt\" src=\"data:{};base64,{}\">\n", x0, y0, x1 - x0, y1 - y0, mime, b64(data))),
            Blk::Text { lines, .. } => for l in lines {
                let sz = l.runs.iter().map(|r| r.size).fold(0.0f32, f32::max);
                o.push_str(&format!("<div class=\"l\" style=\"left:{:.2}pt;top:{:.2}pt;height:{:.2}pt;line-height:{:.2}pt;font-size:{:.1}pt\">", l.x0, l.y0, l.y1 - l.y0, l.y1 - l.y0, sz));
                for r in &l.runs { o.push_str(&format!("<span style=\"font-family:'{}',Arial,sans-serif;font-size:{:.1}pt;color:#{:06x}{}{}\">{}</span>", esc(&family(&r.font)), r.size, r.rgb, if r.bold { ";font-weight:bold" } else { "" }, if r.italic { ";font-style:italic" } else { "" }, esc(&r.text))); }
                o.push_str("</div>\n");
            } } }
        o.push_str("</div>\n");
    }
    o.push_str("</body></html>\n"); o
}

fn crc32(d: &[u8]) -> u32 { let mut c = !0u32; for &b in d { c ^= b as u32; for _ in 0..8 { c = if c & 1 != 0 { (c >> 1) ^ 0xEDB8_8320 } else { c >> 1 }; } } !c }
fn zip_store(files: &[(String, Vec<u8>)]) -> Vec<u8> {
    let mut o: Vec<u8> = vec![]; let mut cd: Vec<u8> = vec![];
    for (name, d) in files {
        let off = o.len() as u32; let crc = crc32(d); let nb = name.as_bytes();
        o.extend_from_slice(&[0x50, 0x4b, 3, 4, 20, 0, 0, 8, 0, 0, 0, 0, 0x21, 0]); // flags: UTF-8 names, method stored, 1980-01-01
        o.extend_from_slice(&crc.to_le_bytes()); o.extend_from_slice(&(d.len() as u32).to_le_bytes()); o.extend_from_slice(&(d.len() as u32).to_le_bytes());
        o.extend_from_slice(&(nb.len() as u16).to_le_bytes()); o.extend_from_slice(&0u16.to_le_bytes()); o.extend_from_slice(nb); o.extend_from_slice(d);
        cd.extend_from_slice(&[0x50, 0x4b, 1, 2, 20, 0, 20, 0, 0, 8, 0, 0, 0, 0, 0x21, 0]);
        cd.extend_from_slice(&crc.to_le_bytes()); cd.extend_from_slice(&(d.len() as u32).to_le_bytes()); cd.extend_from_slice(&(d.len() as u32).to_le_bytes());
        cd.extend_from_slice(&(nb.len() as u16).to_le_bytes()); cd.extend_from_slice(&[0; 12]); cd.extend_from_slice(&off.to_le_bytes()); cd.extend_from_slice(nb);
    }
    let cdoff = o.len() as u32; o.extend_from_slice(&cd);
    o.extend_from_slice(&[0x50, 0x4b, 5, 6, 0, 0, 0, 0]); o.extend_from_slice(&(files.len() as u16).to_le_bytes()); o.extend_from_slice(&(files.len() as u16).to_le_bytes());
    o.extend_from_slice(&(cd.len() as u32).to_le_bytes()); o.extend_from_slice(&cdoff.to_le_bytes()); o.extend_from_slice(&0u16.to_le_bytes()); o
}

/// A Word file: each PDF page is its own section with the original page size; text keeps its fonts, sizes, colours, line breaks and indents; pictures are inline.
fn docx_doc(pages: &[Pg]) -> Vec<u8> {
    let mut media: Vec<(String, Vec<u8>)> = vec![]; let mut rels = String::new(); let mut body = String::new();
    let tw = |pt: f32| (pt * 20.0).round() as i64;
    for (pi, p) in pages.iter().enumerate() {
        let margin = 36.0f32; let cw = (p.w - 2.0 * margin).max(72.0);
        let mut prev_y = margin.min(p.blocks.iter().map(|b| match b { Blk::Text { y0, .. } | Blk::Img { y0, .. } => *y0 }).fold(f32::MAX, f32::min));
        let nb = p.blocks.len(); let mut last_open = false;
        let mut pending_sect = true;
        for (bi, b) in p.blocks.iter().enumerate() {
            let last = bi + 1 == nb;
            let sect = if last { pending_sect = false; format!("<w:sectPr><w:pgSz w:w=\"{}\" w:h=\"{}\"/><w:pgMar w:top=\"720\" w:right=\"720\" w:bottom=\"720\" w:left=\"720\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>", tw(p.w), tw(p.h)) } else { String::new() };
            match b {
                Blk::Text { x0, y0, y1, lines } => {
                    let before = tw((y0 - prev_y).max(0.0).min(p.h)); prev_y = *y1;
                    body.push_str(&format!("<w:p><w:pPr><w:spacing w:before=\"{}\" w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/><w:ind w:left=\"{}\"/>{}</w:pPr>", before, tw((x0 - margin).max(0.0).min(cw * 0.8)), sect));
                    for (li, l) in lines.iter().enumerate() {
                        if li > 0 { body.push_str("<w:r><w:br/></w:r>"); }
                        for r in &l.runs {
                            let f = esc(&family(&r.font));
                            body.push_str(&format!("<w:r><w:rPr><w:rFonts w:ascii=\"{f}\" w:hAnsi=\"{f}\" w:cs=\"{f}\"/>{}{}<w:color w:val=\"{:06X}\"/><w:sz w:val=\"{}\"/><w:szCs w:val=\"{}\"/></w:rPr><w:t xml:space=\"preserve\">{}</w:t></w:r>", if r.bold { "<w:b/>" } else { "" }, if r.italic { "<w:i/>" } else { "" }, r.rgb, (r.size * 2.0).round() as i32, (r.size * 2.0).round() as i32, esc(&r.text)));
                        }
                    }
                    body.push_str("</w:p>");
                }
                Blk::Img { x0, y0, x1, y1, mime, data } => {
                    let before = tw((y0 - prev_y).max(0.0).min(p.h)); prev_y = *y1;
                    let ext = if *mime == "image/png" { "png" } else { "jpg" }; let id = media.len() + 1; let name = format!("img{id}.{ext}"); media.push((format!("word/media/{name}"), data.clone()));
                    rels.push_str(&format!("<Relationship Id=\"rIdImg{id}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/{name}\"/>"));
                    let (mut w, mut h) = ((x1 - x0).max(1.0), (y1 - y0).max(1.0)); if w > cw { h *= cw / w; w = cw; }
                    let (cx, cy) = ((w * 12700.0) as i64, (h * 12700.0) as i64);
                    body.push_str(&format!("<w:p><w:pPr><w:spacing w:before=\"{}\" w:after=\"0\"/><w:ind w:left=\"{}\"/>{}</w:pPr><w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"{cx}\" cy=\"{cy}\"/><wp:docPr id=\"{id}\" name=\"Picture {id}\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"{id}\" name=\"{name}\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"rIdImg{id}\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"{cx}\" cy=\"{cy}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>", before, tw((x0 - margin).max(0.0).min(cw * 0.8)), sect));
                }
            }
            last_open = true;
        }
        if nb == 0 { body.push_str(&format!("<w:p><w:pPr><w:sectPr><w:pgSz w:w=\"{}\" w:h=\"{}\"/><w:pgMar w:top=\"720\" w:right=\"720\" w:bottom=\"720\" w:left=\"720\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr></w:pPr></w:p>", tw(p.w), tw(p.h))); }
        let _ = (pi, last_open, pending_sect);
    }
    let doc = format!("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\"><w:body>{body}</w:body></w:document>");
    let mut files: Vec<(String, Vec<u8>)> = vec![
        ("[Content_Types].xml".into(), b"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>".to_vec()),
        ("_rels/.rels".into(), b"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>".to_vec()),
        ("word/document.xml".into(), doc.into_bytes()),
        ("word/_rels/document.xml.rels".into(), format!("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">{rels}</Relationships>").into_bytes()),
    ];
    files.extend(media); zip_store(&files)
}

/// Converts one image file (PNG, JPEG, BMP, TIFF, GIF...) into a one-page PDF.
pub fn image_to_pdf(src: &str, out: &Path) -> Result<(), String> {
    let d = Document::open(src).map_err(|e| e.to_string())?;
    let n = d.page_count().map_err(|e| e.to_string())?;
    let mut p = d.convert_to_pdf(0, n - 1, 0).map_err(|e| e.to_string())?;
    p.save(&out.to_string_lossy()).map_err(|e| e.to_string())
}
