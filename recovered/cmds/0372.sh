cd /tmp/scratch/app/src && cat >> ops.rs <<'EOF'

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
EOF
python3 - <<'EOF'
s=open('extras.rs').read()
# AI: chat history
a=s.index("// ---------- AI ----------"); b=s.index("pub fn ai_post")
new='''// ---------- AI ----------
/// history: (is_user, text). The whole conversation is sent every time; context (page text) goes in as the system part. No retrieval layer.
pub fn ai_chat(s: &Settings, history: &[(bool, String)], context: Option<&str>, image_jpeg_b64: Option<&str>) -> Result<String, String> {
    if s.key.trim().is_empty() { return Err("Add your API key first.".into()); }
    if s.model.trim().is_empty() { return Err("Type a model name first.".into()); }
    if history.is_empty() { return Err("Nothing to send.".into()); }
    let sys = "You are an assistant inside a PDF reader. Answer using the document context when it is provided. Use Markdown only for headings, bullet lists, **bold**, `code` and fenced code blocks.";
    let ctx = match context { Some(c) if !c.trim().is_empty() => format!("{sys}\\n\\nDocument context:\\n{c}"), _ => sys.to_string() };
    let last = history.len() - 1;
    let gemini = s.provider == "Gemini";
    let (url, header, body) = if gemini {
        let contents: Vec<Value> = history.iter().enumerate().map(|(i, (u, t))| {
            let mut parts = vec![json!({"text": t})];
            if i == last && *u { if let Some(img) = image_jpeg_b64 { parts.push(json!({"inline_data": {"mime_type": "image/jpeg", "data": img}})); } }
            json!({"role": if *u { "user" } else { "model" }, "parts": parts}) }).collect();
        (format!("https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent", s.model.trim()), format!("x-goog-api-key: {}", s.key.trim()),
         json!({"system_instruction": {"parts": [{"text": ctx}]}, "contents": contents}))
    } else {
        let mut msgs = vec![json!({"role": "system", "content": ctx})];
        for (i, (u, t)) in history.iter().enumerate() {
            if i == last && *u && image_jpeg_b64.is_some() { msgs.push(json!({"role": "user", "content": [{"type": "text", "text": t}, {"type": "image_url", "image_url": {"url": format!("data:image/jpeg;base64,{}", image_jpeg_b64.unwrap())}}]})); }
            else { msgs.push(json!({"role": if *u { "user" } else { "assistant" }, "content": t})); }
        }
        ("https://openrouter.ai/api/v1/chat/completions".to_string(), format!("Authorization: Bearer {}", s.key.trim()), json!({"model": s.model.trim(), "messages": msgs}))
    };
    ai_post(&url, &header, &body, gemini)
}
'''
s=s[:a]+new+s[b:]
# OCR doc with range + log + retries
a=s.index("pub fn ocr_bmp"); b=s.index("pub fn write_bmp")
ocr='''fn ocr_log(line: &str) {
    let p = settings_path().with_file_name("ocr.log");
    if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) { let _ = writeln!(f, "{line}"); }
}
pub fn ocr_bmp(bmp: &std::path::Path, psm: u32) -> Result<Vec<crate::ops::OcrWord>, String> {
    let td = exe_dir().join("ocr").join("tessdata");
    let out = bmp.with_extension("");
    let mut c = Command::new(tess_exe()); nowin(&mut c);
    if td.exists() { c.arg("--tessdata-dir").arg(&td); }
    let r = c.arg(bmp).arg(&out).args(["-l", "eng", "--psm", &psm.to_string(), "-c", "tessedit_create_tsv=1"]).output().map_err(|e| format!("OCR engine missing: {e}"))?;
    let err = String::from_utf8_lossy(&r.stderr).replace('\\n', " | ");
    if !r.status.success() { ocr_log(&format!("tesseract exit {:?}: {}", r.status.code(), err)); return Err(format!("OCR engine failed: {}", err.chars().take(200).collect::<String>())); }
    let tsvp = out.with_extension("tsv");
    let tsv = std::fs::read_to_string(&tsvp).map_err(|e| format!("no OCR output file ({e}); engine said: {}", err.chars().take(200).collect::<String>()))?;
    let _ = std::fs::remove_file(&tsvp); let _ = std::fs::remove_file(out.with_extension("txt"));
    let mut words = vec![];
    for l in tsv.lines().skip(1) {
        let f: Vec<&str> = l.split('\\t').collect();
        if f.len() < 12 || f[0] != "5" { continue; }
        let t = f[11].trim(); if t.is_empty() { continue; }
        if let (Ok(x), Ok(y), Ok(w), Ok(h)) = (f[6].parse(), f[7].parse(), f[8].parse(), f[9].parse()) { words.push(crate::ops::OcrWord { text: t.to_string(), x, y, w, h }); }
    }
    Ok(words)
}

/// OCR pages from..=to (0-based) in place (invisible text layer, page size unchanged). Returns (words, pages_with_words).
pub fn ocr_document(doc: &mut mupdf::pdf::PdfDocument, from: usize, to: usize, progress: &mut dyn FnMut(usize, usize, usize)) -> Result<(usize, usize), String> {
    use mupdf::{Colorspace, Matrix};
    let n = doc.page_count().map_err(|e| e.to_string())? as usize; let to = to.min(n.saturating_sub(1));
    let dpi = 300.0f32; let (mut total, mut good) = (0, 0); let count = to + 1 - from;
    ocr_log(&format!("--- OCR pages {}-{} of {}", from + 1, to + 1, n));
    for i in from..=to {
        progress(i - from, count, total);
        let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
        let b = pg.bounds().map_err(|e| e.to_string())?;
        // keep huge pages from exploding: cap the long side at ~7000 px
        let long = (b.x1 - b.x0).max(b.y1 - b.y0).max(1.0); let d = dpi.min(7000.0 / long * 72.0);
        let s = d / 72.0;
        let pm = pg.to_pixmap(&Matrix::new_scale(s, s), &Colorspace::device_rgb(), false, true).map_err(|e| e.to_string())?;
        let bmp = std::env::temp_dir().join(format!("litepdf-ocr-{}-{i}.bmp", std::process::id()));
        write_bmp(&bmp, pm.width() as usize, pm.height() as usize, pm.samples()).map_err(|e| e.to_string())?;
        let mut words = ocr_bmp(&bmp, 3)?;
        if words.is_empty() { words = ocr_bmp(&bmp, 6)?; }
        if words.is_empty() { words = ocr_bmp(&bmp, 11)?; }
        let _ = std::fs::remove_file(&bmp);
        ocr_log(&format!("page {} {}x{}px dpi {:.0}: {} words", i + 1, pm.width(), pm.height(), d, words.len()));
        if !words.is_empty() { good += 1; total += words.len(); crate::ops::add_text_layer(doc, i as i32, &words, d).map_err(|e| e.to_string())?; }
    }
    Ok((total, good))
}
'''
s=s[:a]+ocr+s[b:]
open('extras.rs','w').write(s)
EOF
grep -n "fn ocr_log\|fn ocr_bmp\|fn ocr_document\|fn write_bmp" extras.rs; echo "18:40 ops freetext edit fns, extras ai_chat + ocr range/log/retries done; next app.rs UI patch" >> ~/NOTES_native.md
