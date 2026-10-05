cd /tmp/scratch/app/src; python3 - <<'E'
s=open('extras.rs').read()
a=s.index("pub struct OcrStats"); b=s.index("// ---------- certificate signing ----------")
new=r'''pub struct OcrStats { pub words: usize, pub done: usize, pub skipped: usize, pub empty: usize, pub failed: usize, pub engine: String }

/// (working set MB, peak working set MB) of this process.
pub fn mem_mb() -> (u64, u64) {
    #[cfg(windows)]
    {
        #[repr(C)] struct Pmc { cb: u32, pf: u32, peak_ws: usize, ws: usize, a: usize, b: usize, c: usize, d: usize, e: usize, f: usize }
        extern "system" { fn GetCurrentProcess() -> isize; fn K32GetProcessMemoryInfo(h: isize, p: *mut Pmc, cb: u32) -> i32; }
        let mut m = Pmc { cb: std::mem::size_of::<Pmc>() as u32, pf: 0, peak_ws: 0, ws: 0, a: 0, b: 0, c: 0, d: 0, e: 0, f: 0 };
        if unsafe { K32GetProcessMemoryInfo(GetCurrentProcess(), &mut m, m.cb) } != 0 { return ((m.ws >> 20) as u64, (m.peak_ws >> 20) as u64); }
        (0, 0)
    }
    #[cfg(not(windows))]
    { let r = std::fs::read_to_string("/proc/self/statm").unwrap_or_default(); let p: u64 = r.split_whitespace().nth(1).and_then(|x| x.parse().ok()).unwrap_or(0); (p * 4096 >> 20, p * 4096 >> 20) }
}

fn page_has_text(doc: &mupdf::pdf::PdfDocument, i: usize) -> bool {
    let Ok(pg) = doc.load_page(i as i32) else { return false };
    let Ok(tp) = pg.to_text_page(mupdf::TextPageFlags::empty()) else { return false };
    tp.to_text().map(|t| t.chars().filter(|c| !c.is_whitespace()).count() >= 10).unwrap_or(false)
}

const RECYCLE_PAGES: usize = 40;      // the worker process restarts after this many pages ...
const RECYCLE_MB: u64 = 1200;         // ... or when its working set passes this

/// Child process entry (`litepdf --ocr <pdf> <pages csv> <gpu 0|1>`): reads the pages, writes one line per event to stdout.
/// Lines: "E engine|note", "S stage", "P {json}", "F page|error", "M page|ws|peak", "DONE", "RECYCLE".
pub fn ocr_child_main(args: &[String]) -> i32 {
    use mupdf::{Colorspace, Matrix};
    fn out(s: &str) { println!("{s}"); }
    let (pdf, pages, gpu) = (&args[0], &args[1], args.get(2).map(|x| x == "1").unwrap_or(true));
    let pages: Vec<usize> = pages.split(',').filter_map(|x| x.trim().parse().ok()).collect();
    crate::ocr::HOOK.set(|s| println!("S {s}")).ok();
    let dir = exe_dir().join("ocr");
    let dll = exe_dir().join(if cfg!(windows) { "onnxruntime.dll" } else { "libonnxruntime.so" });
    let mut eng = match crate::ocr::Engine::new(&dir, &dll, gpu) { Ok(e) => e, Err(e) => { out(&format!("X engine: {}", e.replace('\n', " "))); return 2; } };
    out(&format!("E {}|{}", eng.provider, eng.note.replace('\n', " ")));
    if let Err(e) = eng.warm_up() {
        out(&format!("S GPU warm-up failed ({}), using CPU", e.replace('\n', " ")));
        eng = match crate::ocr::Engine::new(&dir, &dll, false) { Ok(e) => e, Err(e) => { out(&format!("X engine: {}", e.replace('\n', " "))); return 2; } };
        out(&format!("E {}|GPU warm-up failed", eng.provider));
    }
    let doc = match mupdf::Document::open(pdf.as_str()) { Ok(d) => d, Err(e) => { out(&format!("X open: {e}")); return 2; } };
    let mut n = 0usize;
    for &i in &pages {
        crate::ocr::stage(&format!("page {} render", i + 1));
        let t = std::time::Instant::now();
        let r = (|| -> Result<(Vec<u8>, usize, usize, f32), String> {
            let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
            let b = pg.bounds().map_err(|e| e.to_string())?;
            let long = (b.x1 - b.x0).max(b.y1 - b.y0).max(1.0); let d = 200.0f32.min(4500.0 / long * 72.0); let s = d / 72.0;
            let pm = pg.to_pixmap(&Matrix::new_scale(s, s), &Colorspace::device_rgb(), false, true).map_err(|e| e.to_string())?;
            Ok((pm.samples().to_vec(), pm.width() as usize, pm.height() as usize, d))
        })();
        let (rgb, w, h, dpi) = match r { Ok(x) => x, Err(e) => { out(&format!("F {i}|{}", e.replace('\n', " "))); continue; } };
        let mut res = eng.recognize(&rgb, w, h);
        if res.is_err() && eng.provider.starts_with("DirectML") {
            out(&format!("S GPU run failed ({}), switching to CPU", res.as_ref().err().cloned().unwrap_or_default().replace('\n', " ")));
            match crate::ocr::Engine::new(&dir, &dll, false) { Ok(c) => { eng = c; out(&format!("E {}|switched to CPU after a GPU error", eng.provider)); res = eng.recognize(&rgb, w, h); } Err(e) => { res = Err(e); } }
        }
        match res {
            Ok(words) => {
                let ws: Vec<serde_json::Value> = words.iter().map(|x| serde_json::json!([x.text, x.x, x.y, x.w, x.h])).collect();
                out(&format!("P {}", serde_json::json!({"p": i, "dpi": dpi, "secs": t.elapsed().as_secs_f32(), "eng": eng.provider, "w": ws})));
            }
            Err(e) => out(&format!("F {i}|{}", e.replace('\n', " "))),
        }
        let (ws, peak) = mem_mb();
        out(&format!("M {i}|{ws}|{peak}"));
        n += 1;
        if n >= RECYCLE_PAGES || ws > RECYCLE_MB { if pages.last() != Some(&i) { out("RECYCLE"); return 0; } }
    }
    out("DONE");
    0
}

/// OCR pages from..=to (0-based) in place (invisible text layer, page size unchanged). Pages that already hold text are skipped unless `force`.
/// The recognition runs in a child process so a crash in the GPU runtime cannot take the app down; after a crash the rest runs on the CPU.
pub fn ocr_document(snap: &str, doc: &mut mupdf::pdf::PdfDocument, from: usize, to: usize, force: bool, progress: &mut dyn FnMut(String)) -> Result<OcrStats, String> {
    use std::io::BufRead;
    let n = doc.page_count().map_err(|e| e.to_string())? as usize; let to = to.min(n.saturating_sub(1));
    ocr_log(&format!("--- OCR pages {}-{} of {} (force={force})", from + 1, to + 1, n));
    let mut stats = OcrStats { words: 0, done: 0, skipped: 0, empty: 0, failed: 0, engine: String::new() };
    let mut pages = vec![];
    for i in from..=to { if !force && page_has_text(doc, i) { stats.skipped += 1; ocr_log(&format!("page {} already has text, skipped", i + 1)); } else { pages.push(i); } }
    if pages.is_empty() { return Ok(stats); }
    let t0 = std::time::Instant::now();
    let total = pages.len();
    let mut remaining: Vec<usize> = pages.clone();
    let mut gpu = true; let mut crashes = 0usize; let mut handled = 0usize;
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let errlog = settings_path().with_file_name("ocr_child_stderr.log");
    while !remaining.is_empty() {
        progress(format!("Starting OCR engine ({})...", if gpu { "GPU" } else { "CPU" }));
        ocr_log(&format!("starting worker process: {} pages left, gpu={gpu}", remaining.len()));
        let csv: String = remaining.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(",");
        let mut cmd = Command::new(&exe); nowin(&mut cmd);
        cmd.arg("--ocr").arg(snap).arg(&csv).arg(if gpu { "1" } else { "0" }).stdout(Stdio::piped());
        match std::fs::OpenOptions::new().create(true).append(true).open(&errlog) { Ok(f) => { cmd.stderr(Stdio::from(f)); } Err(_) => { cmd.stderr(Stdio::null()); } }
        let mut child = cmd.spawn().map_err(|e| format!("could not start the OCR worker: {e}"))?;
        let rd = std::io::BufReader::new(child.stdout.take().ok_or("no worker output")?);
        let mut last_stage = String::new(); let mut done_pages: Vec<usize> = vec![]; let mut finished = false; let mut recycle = false; let mut fatal: Option<String> = None;
        for line in rd.lines() {
            let Ok(line) = line else { break };
            let (tag, rest) = line.split_at(line.find(' ').unwrap_or(line.len())); let rest = rest.trim_start();
            match tag {
                "E" => { let mut it = rest.splitn(2, '|'); stats.engine = it.next().unwrap_or("").to_string(); ocr_log(&format!("engine: {} {}", stats.engine, it.next().unwrap_or(""))); }
                "S" => { last_stage = rest.to_string(); ocr_log(&format!("  stage: {rest}")); }
                "M" => { ocr_log(&format!("  memory (worker): {rest} MB (working set | peak)")); }
                "X" => { fatal = Some(rest.to_string()); ocr_log(&format!("worker error: {rest}")); }
                "F" => {
                    let (p, e) = rest.split_once('|').unwrap_or((rest, "")); let p: usize = p.parse().unwrap_or(0);
                    ocr_log(&format!("page {} failed: {e}", p + 1)); stats.failed += 1; done_pages.push(p); handled += 1;
                }
                "P" => {
                    let Ok(v) = serde_json::from_str::<serde_json::Value>(rest) else { continue };
                    let p = v["p"].as_u64().unwrap_or(0) as usize; let dpi = v["dpi"].as_f64().unwrap_or(200.0) as f32;
                    let ws: Vec<crate::ops::OcrWord> = v["w"].as_array().map(|a| a.iter().filter_map(|w| Some(crate::ops::OcrWord { text: w[0].as_str()?.to_string(), x: w[1].as_f64()? as f32, y: w[2].as_f64()? as f32, w: w[3].as_f64()? as f32, h: w[4].as_f64()? as f32 })).collect()).unwrap_or_default();
                    ocr_log(&format!("page {} {:.1}s {}: {} words", p + 1, v["secs"].as_f64().unwrap_or(0.0), v["eng"].as_str().unwrap_or(""), ws.len()));
                    done_pages.push(p); handled += 1;
                    if ws.is_empty() { stats.empty += 1; } else {
                        stats.words += ws.len(); stats.done += 1;
                        ocr_log(&format!("  stage: page {} text layer", p + 1));
                        if let Err(e) = crate::ops::add_text_layer(doc, p as i32, &ws, dpi) { ocr_log(&format!("text layer failed on page {}: {e}", p + 1)); stats.failed += 1; }
                    }
                    progress(format!("OCR {} of {} pages ({} words, {}s, {})", handled, total, stats.words, t0.elapsed().as_secs(), stats.engine));
                }
                "RECYCLE" => { recycle = true; ocr_log("worker restarts to release memory"); }
                "DONE" => { finished = true; }
                _ => {}
            }
        }
        let status = child.wait().ok();
        remaining.retain(|p| !done_pages.contains(p));
        if finished || (recycle && fatal.is_none()) { if finished { remaining.clear(); } continue; }
        // the worker ended without finishing: crash or engine failure
        crashes += 1;
        let code = status.and_then(|s| s.code()).map(|c| format!("{c} (0x{:08X})", c as u32)).unwrap_or_else(|| "none".into());
        ocr_log(&format!("WORKER ENDED EARLY: exit code {code}, last stage: {last_stage}, {} pages left", remaining.len()));
        if fatal.is_some() && !gpu { return Err(format!("OCR engine could not start: {}", fatal.unwrap_or_default())); }
        if crashes > 30 { return Err("OCR worker kept crashing; see ocr.log".into()); }
        if gpu { gpu = false; ocr_log("retrying the rest on the CPU"); progress("GPU engine stopped, continuing on CPU...".into()); stats.engine = "CPU (after GPU error)".into(); }
        else if let Some(&bad) = remaining.first() { ocr_log(&format!("page {} crashed the CPU worker too, skipping it", bad + 1)); stats.failed += 1; remaining.remove(0); }
    }
    ocr_log(&format!("done: {} words on {} pages ({} failed) in {:?}", stats.words, stats.done, stats.failed, t0.elapsed()));
    Ok(stats)
}

'''
s=s[:a]+new+s[b:]
open('extras.rs','w').write(s)
E
grep -n "^fn settings_path\|pub fn exe_dir" extras.rs; sed -i 's/^fn settings_path/pub fn settings_path/' extras.rs; grep -n "OcrStats {" extras.rs | head -3
