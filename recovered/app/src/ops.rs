//! Document-level operations (merge, split, reorder, delete, rotate, compress, encrypt, redact). Pure MuPDF.
use mupdf::pdf::{PdfDocument, PdfWriteOptions, Encryption, Permission};
use mupdf::Error;

const INH: [&str; 4] = ["Resources", "MediaBox", "CropBox", "Rotate"];

fn page_objs(doc: &PdfDocument, idx: &[usize]) -> Result<Vec<mupdf::pdf::PdfObject>, Error> {
    let mut out = vec![];
    for &i in idx {
        let mut p = doc.find_page(i as i32)?;
        for k in INH {
            if p.get_dict(k)?.is_none() {
                if let Some(v) = p.get_dict_inheritable(k)? { p.dict_put(k, v)?; }
            }
        }
        out.push(p);
    }
    Ok(out)
}

/// Keep only `order` pages (in that order). Used for delete, reorder and split.
pub fn keep_pages(doc: &mut PdfDocument, order: &[usize]) -> Result<(), Error> {
    let mut pages = doc.catalog()?.get_dict("Pages")?.ok_or(Error::InvalidArgument("no Pages".into()))?;
    let objs = page_objs(doc, order)?;
    let mut kids = doc.new_array()?;
    for mut p in objs {
        p.dict_put("Parent", pages.clone())?;
        kids.array_push(p)?;
    }
    pages.dict_put("Kids", kids)?;
    pages.dict_put("Count", doc.new_int(order.len() as i32)?)?;
    Ok(())
}

/// Append all pages of `src` to `dst`.
pub fn append(dst: &mut PdfDocument, src: &PdfDocument) -> Result<(), Error> {
    let n = src.page_count()? as usize;
    let mut gm = dst.new_graft_map()?;
    let mut pages = dst.catalog()?.get_dict("Pages")?.ok_or(Error::InvalidArgument("no Pages".into()))?;
    let mut kids = pages.get_dict("Kids")?.ok_or(Error::InvalidArgument("no Kids".into()))?;
    let objs = page_objs(src, &(0..n).collect::<Vec<_>>())?;
    let mut added = 0;
    for p in objs {
        let mut g = gm.graft_object(&p)?;
        g.dict_put("Parent", pages.clone())?;
        kids.array_push(dst.add_object(&g)?)?;
        added += 1;
    }
    let cnt = pages.get_dict("Count")?.map(|c| c.as_int().unwrap_or(0)).unwrap_or(0);
    pages.dict_put("Count", dst.new_int(cnt + added)?)?;
    Ok(())
}

pub fn save(doc: &PdfDocument, out: &str, compact: bool) -> Result<(), Error> {
    let mut o = PdfWriteOptions::default();
    if compact { o.set_garbage_level(3); o.set_compress(true); o.set_clean(true); }
    doc.save_with_options(out, o)
}

/// Faster save for large documents: compress streams, no garbage collection or cleaning.
pub fn save_fast(doc: &PdfDocument, out: &str) -> Result<(), Error> {
    let mut o = PdfWriteOptions::default(); o.set_compress(true);
    doc.save_with_options(out, o)
}

pub fn merge(inputs: &[&str], out: &str) -> Result<(), Error> {
    let mut d = PdfDocument::open(inputs[0])?;
    for p in &inputs[1..] { let s = PdfDocument::open(*p)?; append(&mut d, &s)?; }
    save(&d, out, true)
}

pub fn split_ranges(input: &str, ranges: &[(usize, usize)], out_prefix: &str) -> Result<Vec<String>, Error> {
    let mut outs = vec![];
    for (k, (a, b)) in ranges.iter().enumerate() {
        let mut d = PdfDocument::open(input)?;
        let order: Vec<usize> = (*a..=*b).collect();
        keep_pages(&mut d, &order)?;
        let name = format!("{out_prefix}_{}.pdf", k + 1);
        save(&d, &name, true)?;
        outs.push(name);
    }
    Ok(outs)
}

pub fn reorder(input: &str, order: &[usize], out: &str) -> Result<(), Error> {
    let mut d = PdfDocument::open(input)?;
    keep_pages(&mut d, order)?;
    save(&d, out, true)
}

pub fn encrypt(input: &str, out: &str, user_pw: &str, owner_pw: &str, perms: Permission) -> Result<(), Error> {
    let d = PdfDocument::open(input)?;
    let mut o = PdfWriteOptions::default();
    o.set_encryption(Encryption::Aes256);
    o.set_user_password(user_pw);
    o.set_owner_password(owner_pw);
    o.set_permissions(perms);
    d.save_with_options(out, o)
}

pub fn decrypt(input: &str, password: &str, out: &str) -> Result<(), Error> {
    let mut d = PdfDocument::open(input)?;
    if d.needs_password()? { if !d.authenticate(password)? { return Err(Error::InvalidArgument("wrong password".into())); } }
    let mut o = PdfWriteOptions::default();
    o.set_encryption(Encryption::None);
    d.save_with_options(out, o)
}

use mupdf::{Rect, TextPageFlags, Quad};
use mupdf::pdf::PageImageSource;

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

/// Downsample large images and re-encode them as JPEG (raw, Flate, JPEG and ICC based RGB/gray images), then garbage-collect.
/// An image is replaced only when the new data is clearly smaller than the stream it replaces.
pub fn compress(input: &str, out: &str, max_dim: u32, quality: u8) -> Result<(usize, usize), Error> {
    let mut d = PdfDocument::open(input)?;
    let mut done = std::collections::HashSet::new();
    let (mut replaced, mut seen) = (0, 0);
    for pi in 0..d.page_count()? {
        let mut page = d.load_pdf_page(pi)?;
        for info in page.images()? {
            if !done.insert(info.xref) { continue; }
            seen += 1;
            if info.bits_per_component.map(|b| b != 8).unwrap_or(false) { continue; }
            let cs = info.color_space.clone().unwrap_or_default();
            if cs.contains("Indexed") || cs.contains("Separation") || cs.contains("DeviceN") || cs.contains("CMYK") || cs.contains("Lab") { continue; }
            if !(cs.contains("DeviceRGB") || cs.contains("DeviceGray") || cs.contains("ICC") || cs.contains("CalRGB") || cs.contains("CalGray")) { continue; }
            let Ok(o) = d.new_indirect(info.xref, 0) else { continue };
            if o.get_dict("SMask").ok().flatten().is_some() || o.get_dict("Mask").ok().flatten().is_some() || o.get_dict("Decode").ok().flatten().is_some() { continue; }
            let orig_len = o.get_dict("Length").ok().flatten().and_then(|l| l.resolve().ok().flatten().unwrap_or(l).as_int().ok()).unwrap_or(i32::MAX) as usize;
            let Ok(raw) = o.read_stream() else { continue };
            let (w0, h0) = (info.width as usize, info.height as usize);
            if w0 == 0 || h0 == 0 || raw.len() % (w0 * h0) != 0 { continue; }
            let comps = raw.len() / (w0 * h0);
            if comps != 1 && comps != 3 { continue; }
            let f = ((w0.max(h0) as f32) / max_dim as f32).ceil().max(1.0) as usize;
            let (w, h) = (w0 / f, h0 / f);
            if w == 0 || h == 0 { continue; }
            let mut px = vec![0u8; w * h * comps];
            if f == 1 { px.copy_from_slice(&raw[..w * h * comps]); } else {
                for y in 0..h { for x in 0..w { for c in 0..comps {
                    let mut sum = 0u32;
                    for dy in 0..f { for dx in 0..f { sum += raw[((y * f + dy) * w0 + (x * f + dx)) * comps + c] as u32; } }
                    px[(y * w + x) * comps + c] = (sum / (f * f) as u32) as u8;
                } } }
            }
            let ct = if comps == 3 { jpeg_encoder::ColorType::Rgb } else { jpeg_encoder::ColorType::Luma };
            let mut buf = vec![];
            if jpeg_encoder::Encoder::new(&mut buf, quality).encode(&px, w as u16, h as u16, ct).is_err() { continue; }
            if buf.len() as f32 > orig_len as f32 * 0.9 { continue; }
            if page.replace_image(&mut d, info.xref, PageImageSource::Bytes { data: &buf, format_hint: Some("jpeg") }).is_ok() { replaced += 1; }
        }
    }
    save(&d, out, true)?;
    Ok((replaced, seen))
}

pub struct OcrWord { pub text: String, pub x: f32, pub y: f32, pub w: f32, pub h: f32 } // pixels, top-left origin

/// Adds an invisible (render mode 3) text layer on the ORIGINAL page. Page size, content and look are unchanged.
pub fn add_text_layer(doc: &mut PdfDocument, page_idx: i32, words: &[OcrWord], dpi: f32) -> Result<(), Error> {
    let mut page = doc.load_pdf_page(page_idx)?;
    let b = page.bounds()?;
    let (fname, _, _) = page.insert_font(doc, &mupdf::pdf::InsertFontOptions::new("Cour"))?;
    let s = 72.0 / dpi;
    let mut c = String::from("q\n");
    for w in words {
        let t: String = w.text.chars().filter(|ch| (*ch as u32) >= 32 && (*ch as u32) < 256).collect();
        if t.is_empty() { continue; }
        let size = (w.h * s * 0.85).max(1.0);
        let approx = t.chars().count() as f32 * 0.6 * size;
        let tz = (100.0 * (w.w * s) / approx).clamp(10.0, 400.0);
        let x = b.x0 + w.x * s;
        let y = b.y1 - (w.y + w.h * 0.8) * s;
        let t = format!("{t} "); let esc: String = t.chars().flat_map(|ch| match ch { '(' | ')' | '\\' => vec!['\\', ch], _ => vec![ch] }).collect();
        c.push_str(&format!("BT 3 Tr /{fname} {size:.2} Tf {tz:.1} Tz 1 0 0 1 {x:.2} {y:.2} Tm ({esc}) Tj ET\n"));
    }
    c.push_str("Q\n");
    let bytes: Vec<u8> = c.chars().map(|ch| ch as u32 as u8).collect();
    page.insert_contents(doc, &bytes, true)?;
    Ok(())
}

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

pub fn mark_redact(doc: &mut PdfDocument, page: i32, rect: Rect) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(page)?;
    let mut a = p.add_redact_annotation(rect)?;
    a.update()?; p.update()?;
    Ok(())
}

/// Apply every marked redaction in the document (true removal of the content under the boxes).
pub fn apply_all_redactions(doc: &mut PdfDocument) -> Result<usize, Error> {
    let mut n = 0;
    for i in 0..doc.page_count()? {
        let mut p = doc.load_pdf_page(i)?;
        let c = p.annotations().filter(|a| matches!(a.r#type(), Ok(PdfAnnotationType::Redact))).count();
        if c > 0 { p.apply_redactions()?; p.update()?; n += c; }
    }
    Ok(n)
}

pub fn delete_page(doc: &mut PdfDocument, i: usize) -> Result<(), Error> {
    let n = doc.page_count()? as usize;
    let order: Vec<usize> = (0..n).filter(|k| *k != i).collect();
    keep_pages(doc, &order)
}
pub fn move_page(doc: &mut PdfDocument, i: usize, to: usize) -> Result<(), Error> {
    let n = doc.page_count()? as usize;
    let mut order: Vec<usize> = (0..n).collect();
    let v = order.remove(i); order.insert(to.min(n - 1), v);
    keep_pages(doc, &order)
}
pub fn rotate_page(doc: &mut PdfDocument, i: usize, delta: i32) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(i as i32)?;
    let r = p.rotation()?;
    p.set_rotation((r + delta).rem_euclid(360))
}

/// Reload a document from its own bytes (needed after page-tree edits so the viewer sees them).
pub fn reload(doc: &PdfDocument) -> Result<PdfDocument, Error> {
    let mut buf: Vec<u8> = vec![];
    doc.write_to(&mut buf)?;
    PdfDocument::from_bytes(&buf)
}

#[derive(Clone, Debug)]
pub struct Field { pub xref: i32, pub rect: Rect, pub kind: mupdf::pdf::WidgetType, pub value: String, pub readonly: bool }

pub fn fields(doc: &PdfDocument, page: i32) -> Vec<Field> {
    let mut v = vec![];
    if let Ok(p) = doc.load_pdf_page(page) {
        for w in p.widgets() {
            let (Ok(k), Ok(x)) = (w.r#type(), w.xref()) else { continue };
            let r = w.annotation().rect().unwrap_or(Rect::new(0.0, 0.0, 0.0, 0.0));
            v.push(Field { xref: x, rect: r, kind: k, value: w.value().ok().flatten().unwrap_or_default(), readonly: w.is_readonly().unwrap_or(false) });
        }
    }
    v
}
pub fn set_field(doc: &mut PdfDocument, page: i32, xref: i32, val: &str) -> Result<bool, Error> {
    let p = doc.load_pdf_page(page)?;
    let Some(mut w) = p.load_widget(xref)? else { return Ok(false) };
    let ok = w.set_value(doc, val, false)?;
    w.update()?;
    Ok(ok)
}
pub fn toggle_field(doc: &mut PdfDocument, page: i32, f: &Field) -> Result<bool, Error> {
    let on = !(f.value.is_empty() || f.value == "Off");
    set_field(doc, page, f.xref, if on { "Off" } else { "Yes" })
}

#[derive(Clone, Debug)]
pub struct Ft { pub idx: usize, pub rect: Rect, pub text: String, pub size: f32, pub font: usize, pub color: [f32; 3] }
pub const FONTS: [(&str, &str); 3] = [("Helv", "Sans (Helvetica)"), ("TiRo", "Serif (Times)"), ("Cour", "Mono (Courier)")];
pub fn font_factor(f: usize) -> f32 { match f { 1 => 0.46, 2 => 0.6, _ => 0.52 } }
fn col3(c: Option<mupdf::color::AnnotationColor>) -> [f32; 3] {
    match c { Some(mupdf::color::AnnotationColor::Rgb { red, green, blue }) => [red, green, blue], Some(mupdf::color::AnnotationColor::Gray(g)) => [g, g, g], _ => [0.0, 0.0, 0.0] }
}
/// Existing FreeText annotation under the point (for re-editing).
pub fn freetext_at(doc: &PdfDocument, page: i32, pt: Point) -> Option<Ft> {
    let p = doc.load_pdf_page(page).ok()?;
    let mut found = None;
    for (i, a) in p.annotations().enumerate() {
        if !matches!(a.r#type(), Ok(PdfAnnotationType::FreeText)) { continue; }
        let Ok(b) = a.bounds() else { continue };
        if pt.x >= b.x0 - 2.0 && pt.x <= b.x1 + 2.0 && pt.y >= b.y0 - 2.0 && pt.y <= b.y1 + 2.0 {
            let da = a.default_appearance().ok().flatten();
            let (size, font, color) = match da { Some(d) => (d.size.max(4.0), match d.font_name.as_str() { "TiRo" | "Times-Roman" => 1, "Cour" | "Courier" => 2, _ => 0 }, col3(d.color)), None => (12.0, 0, [0.0; 3]) };
            found = Some(Ft { idx: i, rect: b, text: a.contents().ok().flatten().unwrap_or("").to_string(), size, font, color });
        }
    }
    found
}
pub fn freetext_update(doc: &mut PdfDocument, page: i32, idx: usize, rect: Rect, text: &str, font: usize, size: f32, color: [f32; 3]) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(page)?;
    if text.trim().is_empty() {
        let t = p.annotations().enumerate().find(|(i, _)| *i == idx).map(|(_, a)| a);
        if let Some(a) = t { p.delete_annotation(a)?; p.update()?; }
        return Ok(());
    }
    for (i, mut a) in p.annotations().enumerate() {
        if i == idx {
            a.set_rect(rect)?; a.set_contents(text)?;
            a.set_default_appearance(FONTS[font.min(2)].0, size, Some(rgb(color)))?;
            a.update()?; break;
        }
    }
    p.update()?;
    Ok(())
}
pub fn add_freetext_f(doc: &mut PdfDocument, page: i32, rect: Rect, text: &str, font: usize, size: f32, color: [f32; 3]) -> Result<(), Error> {
    let mut p = doc.load_pdf_page(page)?;
    let mut a = p.add_free_text_annotation(rect, text)?;
    a.set_default_appearance(FONTS[font.min(2)].0, size, Some(rgb(color)))?;
    a.set_border_width(0.0)?;
    a.update()?; p.update()?;
    Ok(())
}
