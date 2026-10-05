cd /tmp/scratch/app/src; python3 - <<'E'
s=open('extras.rs').read()
a=s.index("// ---------- OCR ----------"); b=s.index("// ---------- certificate signing ----------")
new='''// ---------- OCR (PaddleOCR via ONNX Runtime: DirectML GPU, CPU fallback) ----------
pub fn ocr_log(line: &str) {
    let p = settings_path().with_file_name("ocr.log");
    if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) { let _ = writeln!(f, "{line}"); }
}
pub struct OcrStats { pub words: usize, pub done: usize, pub skipped: usize, pub empty: usize, pub engine: String }

fn page_has_text(doc: &mupdf::pdf::PdfDocument, i: usize) -> bool {
    let Ok(pg) = doc.load_page(i as i32) else { return false };
    let Ok(tp) = pg.to_text_page(mupdf::TextPageFlags::empty()) else { return false };
    tp.to_text().map(|t| t.chars().filter(|c| !c.is_whitespace()).count() >= 10).unwrap_or(false)
}

/// OCR pages from..=to (0-based) in place (invisible text layer, page size unchanged). Pages that already hold text are skipped unless `force`.
pub fn ocr_document(doc: &mut mupdf::pdf::PdfDocument, from: usize, to: usize, force: bool, progress: &mut dyn FnMut(String)) -> Result<OcrStats, String> {
    use mupdf::{Colorspace, Matrix};
    use std::sync::mpsc;
    let n = doc.page_count().map_err(|e| e.to_string())? as usize; let to = to.min(n.saturating_sub(1));
    let dir = exe_dir().join("ocr");
    let dll = exe_dir().join(if cfg!(windows) { "onnxruntime.dll" } else { "libonnxruntime.so" });
    ocr_log(&format!("--- OCR pages {}-{} of {} (force={force})", from + 1, to + 1, n));
    let mut stats = OcrStats { words: 0, done: 0, skipped: 0, empty: 0, engine: String::new() };
    let mut pages = vec![];
    for i in from..=to { if !force && page_has_text(doc, i) { stats.skipped += 1; ocr_log(&format!("page {} already has text, skipped", i + 1)); } else { pages.push(i); } }
    if pages.is_empty() { return Ok(stats); }
    progress("Starting OCR engine...".into());
    let t0 = std::time::Instant::now();
    let engine = crate::ocr::Engine::new(&dir, &dll, true).map_err(|e| { ocr_log(&format!("engine start failed: {e}")); format!("OCR engine could not start: {e}") })?;
    stats.engine = engine.provider.clone();
    ocr_log(&format!("engine: {} {} (start {:?})", engine.provider, engine.note, t0.elapsed()));
    struct Job { i: usize, rgb: Vec<u8>, w: usize, h: usize, dpi: f32 }
    struct Res { i: usize, dpi: f32, r: Result<Vec<crate::ocr::Word>, String>, secs: f32, engine: String }
    let (jtx, jrx) = mpsc::sync_channel::<Job>(2); let (rtx, rrx) = mpsc::channel::<Res>();
    let (dir2, dll2) = (dir.clone(), dll.clone());
    let worker = std::thread::spawn(move || {
        let mut e = engine; let mut ok_any = false;
        while let Ok(j) = jrx.recv() {
            let t = std::time::Instant::now();
            let mut r = e.recognize(&j.rgb, j.w, j.h);
            if r.is_err() && !ok_any && e.provider.starts_with("DirectML") {
                ocr_log(&format!("GPU run failed ({}), switching to CPU", r.as_ref().err().unwrap()));
                match crate::ocr::Engine::new(&dir2, &dll2, false) { Ok(c) => { e = c; r = e.recognize(&j.rgb, j.w, j.h); } Err(er) => { r = Err(er); } }
            }
            if r.is_ok() { ok_any = true; }
            let _ = rtx.send(Res { i: j.i, dpi: j.dpi, r, secs: t.elapsed().as_secs_f32(), engine: e.provider.clone() });
        }
    });
    let total = pages.len(); let mut got = 0usize; let mut err: Option<String> = None;
    let mut apply = |doc: &mut mupdf::pdf::PdfDocument, res: Res, stats: &mut OcrStats, got: &mut usize, err: &mut Option<String>| {
        *got += 1; stats.engine = res.engine.clone();
        match res.r {
            Ok(w) => {
                ocr_log(&format!("page {} {:.1}s {}: {} words", res.i + 1, res.secs, res.engine, w.len()));
                if w.is_empty() { stats.empty += 1; } else {
                    let ws: Vec<crate::ops::OcrWord> = w.into_iter().map(|x| crate::ops::OcrWord { text: x.text, x: x.x, y: x.y, w: x.w, h: x.h }).collect();
                    stats.words += ws.len(); stats.done += 1;
                    if let Err(e) = crate::ops::add_text_layer(doc, res.i as i32, &ws, res.dpi) { *err = Some(e.to_string()); }
                }
            }
            Err(e) => { ocr_log(&format!("page {} failed: {e}", res.i + 1)); if err.is_none() { *err = Some(e); } }
        }
    };
    for &i in &pages {
        if err.is_some() { break; }
        while let Ok(res) = rrx.try_recv() { apply(doc, res, &mut stats, &mut got, &mut err); }
        progress(format!("OCR page {} ({} of {}, {} words, {}s, {})", i + 1, got + 1, total, stats.words, t0.elapsed().as_secs(), stats.engine));
        let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
        let b = pg.bounds().map_err(|e| e.to_string())?;
        let long = (b.x1 - b.x0).max(b.y1 - b.y0).max(1.0); let d = 200.0f32.min(4500.0 / long * 72.0); let s = d / 72.0;
        let pm = pg.to_pixmap(&Matrix::new_scale(s, s), &Colorspace::device_rgb(), false, true).map_err(|e| e.to_string())?;
        if jtx.send(Job { i, rgb: pm.samples().to_vec(), w: pm.width() as usize, h: pm.height() as usize, dpi: d }).is_err() { break; }
    }
    drop(jtx);
    while got < total && err.is_none() { match rrx.recv() { Ok(res) => { apply(doc, res, &mut stats, &mut got, &mut err); progress(format!("OCR {} of {} pages ({} words, {}s)", got, total, stats.words, t0.elapsed().as_secs())); } Err(_) => break } }
    let _ = worker.join();
    if let Some(e) = err { return Err(e); }
    ocr_log(&format!("done: {} words on {} pages in {:?}", stats.words, stats.done, t0.elapsed()));
    Ok(stats)
}

'''
s=s[:a]+new+s[b:]
s=s.replace("//! Signing, OCR (bundled Tesseract subprocess)","//! Signing, OCR (PaddleOCR on ONNX Runtime)")
open('extras.rs','w').write(s)

m=open('main.rs').read(); print(m)
E
