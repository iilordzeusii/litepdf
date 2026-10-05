//! Signing, OCR (PaddleOCR on ONNX Runtime) and AI (HTTPS via curl, no RAG: text/image goes straight to the provider).
use serde_json::{json, Value};
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[cfg(windows)]
fn nowin(c: &mut Command) -> &mut Command { use std::os::windows::process::CommandExt; c.creation_flags(0x08000000) }
#[cfg(not(windows))]
fn nowin(c: &mut Command) -> &mut Command { c }

pub fn exe_dir() -> PathBuf { std::env::current_exe().ok().and_then(|p| p.parent().map(|p| p.to_path_buf())).unwrap_or_default() }

// ---------- settings (local file, never in the repo) ----------
#[derive(Clone, Default)]
pub struct Settings { pub provider: String, pub key: String, pub model: String, pub saved: Vec<(String, String, String)> }
impl Settings {
    /// Switch provider: park the current key/model under the old provider, load the stored ones for the new one.
    pub fn switch_to(&mut self, new: &str) {
        if self.provider == new { return; }
        let old = self.provider.clone();
        let loaded = self.saved.iter().position(|(p, _, _)| p == new).map(|i| self.saved.remove(i));
        self.saved.retain(|(p, _, _)| *p != old);
        self.saved.push((old, std::mem::take(&mut self.key), std::mem::take(&mut self.model)));
        if let Some((_, k, m)) = loaded { self.key = k; self.model = m; }
        self.provider = new.to_string();
    }
}
pub fn settings_path() -> PathBuf {
    let base = std::env::var("APPDATA").or_else(|_| std::env::var("XDG_CONFIG_HOME")).unwrap_or_else(|_| std::env::var("HOME").map(|h| format!("{h}/.config")).unwrap_or_default());
    PathBuf::from(base).join("LitePDF").join("settings.json")
}
pub fn load_settings() -> Settings {
    let mut s = Settings { provider: "Gemini".into(), ..Default::default() };
    if let Ok(t) = std::fs::read_to_string(settings_path()) { if let Ok(v) = serde_json::from_str::<Value>(&t) {
        if let Some(x) = v["provider"].as_str() { s.provider = x.into(); }
        if let Some(o) = v["profiles"].as_object() { for (p, pv) in o { let (k, m) = (pv["key"].as_str().unwrap_or("").to_string(), pv["model"].as_str().unwrap_or("").to_string()); if *p == s.provider { s.key = k; s.model = m; } else { s.saved.push((p.clone(), k, m)); } } }
        else { if let Some(x) = v["key"].as_str() { s.key = x.into(); } if let Some(x) = v["model"].as_str() { s.model = x.into(); } } } }
    s
}
pub fn save_settings(s: &Settings) {
    let p = settings_path(); if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
    let mut prof = serde_json::Map::new();
    for (pn, k, m) in &s.saved { prof.insert(pn.clone(), json!({"key": k, "model": m})); }
    prof.insert(s.provider.clone(), json!({"key": s.key, "model": s.model}));
    let _ = std::fs::write(p, json!({"provider": s.provider, "profiles": prof}).to_string());
}

// ---------- AI ----------
/// history: (is_user, text). The whole conversation is sent every time; context (page text) goes in as the system part. No retrieval layer.
pub fn ai_chat(s: &Settings, history: &[(bool, String)], context: Option<&str>, images: &[String]) -> Result<String, String> {
    if s.key.trim().is_empty() { return Err("Add your API key first.".into()); }
    if s.model.trim().is_empty() { return Err("Type a model name first.".into()); }
    if history.is_empty() { return Err("Nothing to send.".into()); }
    let sys = "You are an assistant inside a PDF reader. Answer using the document context when it is provided. Use Markdown only for headings, bullet lists, **bold**, `code` and fenced code blocks.";
    let ctx = match context { Some(c) if !c.trim().is_empty() => format!("{sys}\n\nDocument context:\n{c}"), _ => sys.to_string() };
    let last = history.len() - 1;
    let gemini = s.provider == "Gemini";
    let (url, header, body) = if gemini {
        let contents: Vec<Value> = history.iter().enumerate().map(|(i, (u, t))| {
            let mut parts = vec![json!({"text": t})];
            if i == last && *u { for img in images { parts.push(json!({"inline_data": {"mime_type": "image/jpeg", "data": img}})); } }
            json!({"role": if *u { "user" } else { "model" }, "parts": parts}) }).collect();
        (format!("https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent", s.model.trim()), format!("x-goog-api-key: {}", s.key.trim()),
         json!({"system_instruction": {"parts": [{"text": ctx}]}, "contents": contents}))
    } else {
        let mut msgs = vec![json!({"role": "system", "content": ctx})];
        for (i, (u, t)) in history.iter().enumerate() {
            if i == last && *u && !images.is_empty() { let mut c = vec![json!({"type": "text", "text": t})]; for im in images { c.push(json!({"type": "image_url", "image_url": {"url": format!("data:image/jpeg;base64,{}", im)}})); } msgs.push(json!({"role": "user", "content": c})); }
            else { msgs.push(json!({"role": if *u { "user" } else { "assistant" }, "content": t})); }
        }
        ("https://openrouter.ai/api/v1/chat/completions".to_string(), format!("Authorization: Bearer {}", s.key.trim()), json!({"model": s.model.trim(), "messages": msgs}))
    };
    ai_post(&url, &header, &body, gemini)
}
pub fn ai_post(url: &str, header: &str, body: &Value, gemini: bool) -> Result<String, String> {
    let tmp = std::env::temp_dir().join(format!("litepdf-ai-{}.json", std::process::id()));
    std::fs::write(&tmp, body.to_string()).map_err(|e| e.to_string())?;
    // URL and key go through stdin config so the key never appears in the process list
    let cfg = format!("url = \"{}\"\nheader = \"{}\"\nheader = \"Content-Type: application/json\"\n", url, header.replace('"', ""));
    let mut c = Command::new("curl"); nowin(&mut c);
    let mut ch = c.args(["-sS", "--max-time", "120", "-K", "-", "--data-binary"]).arg(format!("@{}", tmp.display())).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().map_err(|e| format!("curl not found: {e}"))?;
    ch.stdin.take().unwrap().write_all(cfg.as_bytes()).map_err(|e| e.to_string())?;
    let out = ch.wait_with_output().map_err(|e| e.to_string())?;
    let _ = std::fs::remove_file(&tmp);
    if !out.status.success() { return Err(String::from_utf8_lossy(&out.stderr).trim().to_string()); }
    let v: Value = serde_json::from_slice(&out.stdout).map_err(|_| String::from_utf8_lossy(&out.stdout).chars().take(300).collect::<String>())?;
    if let Some(e) = v.get("error") { return Err(e["message"].as_str().unwrap_or(&e.to_string()).to_string()); }
    let t = if gemini { v["candidates"][0]["content"]["parts"].as_array().map(|a| a.iter().filter_map(|p| p["text"].as_str()).collect::<Vec<_>>().join("")) }
            else { v["choices"][0]["message"]["content"].as_str().map(|s| s.to_string()) };
    t.ok_or_else(|| "No text in response".to_string())
}

// ---------- OCR (PaddleOCR via ONNX Runtime: DirectML GPU, CPU fallback) ----------
pub fn ocr_log(line: &str) {
    let p = settings_path().with_file_name("ocr.log");
    if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) { let _ = writeln!(f, "{line}"); }
}
pub struct OcrStats { pub words: usize, pub done: usize, pub skipped: usize, pub empty: usize, pub failed: usize, pub engine: String }

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

pub const BUILD: &str = "LitePDF build 2026-10-04 fixed-shape GPU sessions (b3)";
const RECYCLE_PAGES: usize = 40;      // the worker process restarts after this many pages ...
const RECYCLE_MB: u64 = 2200;         // ... or when its working set passes this

/// Child process entry (`litepdf --ocr <pdf> <pages csv> <gpu 0|1>`): reads the pages, writes one line per event to stdout.
/// Lines: "E engine|note", "S stage", "P {json}", "F page|error", "M page|ws|peak", "DONE", "RECYCLE".
pub fn ocr_child_main(args: &[String]) -> i32 {
    use mupdf::{Colorspace, Matrix};
    fn out(s: &str) { println!("{s}"); }
    let (pdf, pages, gpu) = (&args[0], &args[1], args.get(2).map(|x| x == "1").unwrap_or(true));
    let pages: Vec<usize> = pages.split(',').filter_map(|x| x.trim().parse().ok()).collect();
    crate::ocr::HOOK.set(|s| println!("S {s}")).ok();
    crate::ocr::INFO.set(|s| println!("I {}", s.replace('\n', " "))).ok();
    out(&format!("I {}", BUILD));
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
    let mut n = 0usize; let mut n_gpu = 0usize; let mut gpu_secs = 0f32; let mut bench_done = false;
    for &i in &pages {
        crate::ocr::stage(&format!("page {} render", i + 1));
        let t = std::time::Instant::now(); eng.take_timing();
        let r = (|| -> Result<(Vec<u8>, usize, usize, f32), String> {
            let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
            let b = pg.bounds().map_err(|e| e.to_string())?;
            let long = (b.x1 - b.x0).max(b.y1 - b.y0).max(1.0); let d = 200.0f32.min(4500.0 / long * 72.0); let s = d / 72.0;
            let pm = pg.to_pixmap(&Matrix::new_scale(s, s), &Colorspace::device_rgb(), false, true).map_err(|e| e.to_string())?;
            Ok((pm.samples().to_vec(), pm.width() as usize, pm.height() as usize, d))
        })();
        let (rgb, w, h, dpi) = match r { Ok(x) => x, Err(e) => { out(&format!("F {i}|{}", e.replace('\n', " "))); continue; } };
        let render_ms = t.elapsed().as_secs_f32() * 1000.0;
        let mut res = eng.recognize(&rgb, w, h);
        let page_secs = t.elapsed().as_secs_f32();
        out(&format!("I page {} timing: render {render_ms:.0} ms, {}", i + 1, eng.take_timing().line()));
        if eng.provider.starts_with("DirectML") { n_gpu += 1; if n_gpu >= 3 { gpu_secs += page_secs; } }
        // watchdog: if the GPU stays slow, time the CPU on this same page and keep the faster engine
        if eng.provider.starts_with("DirectML") && n_gpu == 6 && !bench_done { bench_done = true; let avg = gpu_secs / 4.0;
            if avg > 2.5 { out(&format!("I GPU pages 3-6 average {avg:.1} s, timing the CPU on the same page"));
                if let Ok(mut c) = crate::ocr::Engine::new(&dir, &dll, false) { let tb = std::time::Instant::now(); let r = c.recognize(&rgb, w, h); let cs = tb.elapsed().as_secs_f32();
                    out(&format!("I CPU benchmark: {cs:.1} s for the same page ({})", c.provider));
                    if r.is_ok() && cs < avg * 0.8 { out(&format!("I CPU is faster ({cs:.1} s vs {avg:.1} s per page), switching to CPU for the rest")); eng = c; res = r; } else { out("I keeping the GPU"); } } } }
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
    ocr_log(&format!("--- OCR pages {}-{} of {} (force={force}) - {}", from + 1, to + 1, n, BUILD));
    ocr_log(&format!("  display adapters: {}  (DirectML uses adapter 0 by default); CPU threads: {}", gpu_names(), std::thread::available_parallelism().map(|n| n.get()).unwrap_or(0)));
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
                "I" => { ocr_log(&format!("  {rest}")); }
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

// ---------- certificate signing ----------
pub fn sign_pdf(input: &str, p12: &str, password: &str, out: &str, reason: &str) -> Result<(), String> {
    use underskrift::{PdfSigner, SigningOptions, SoftwareSigner, SubFilter};
    let data = std::fs::read(input).map_err(|e| e.to_string())?;
    let signer = SoftwareSigner::from_pkcs12_file(p12, password).map_err(|e| format!("Could not load certificate: {e}"))?;
    let options = SigningOptions { sub_filter: SubFilter::Pades, field_name: "Signature1".to_string(), reason: Some(reason.to_string()), ..Default::default() };
    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().map_err(|e| e.to_string())?;
    let signed = rt.block_on(async { PdfSigner::new().options(options).sign(&data, &signer).await }).map_err(|e| format!("Signing failed: {e}"))?;
    std::fs::write(out, signed).map_err(|e| e.to_string())
}

/// Open a web or mail link in the default handler. Only http, https and mailto are allowed.
pub fn open_url(u: &str) {
    let l = u.to_ascii_lowercase();
    if !(l.starts_with("http://") || l.starts_with("https://") || l.starts_with("mailto:")) { return; }
    #[cfg(windows)]
    { let mut c = Command::new("rundll32.exe"); nowin(&mut c); let _ = c.arg("url.dll,FileProtocolHandler").arg(u).spawn(); }
    #[cfg(not(windows))]
    { let _ = Command::new("xdg-open").arg(u).spawn(); }
}

/// Names of the display adapters (Windows registry), for ocr.log.
pub fn gpu_names() -> String {
    #[cfg(windows)]
    {
        let mut c = Command::new("reg"); nowin(&mut c);
        if let Ok(o) = c.args(["query", r"HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}", "/s", "/v", "DriverDesc"]).output() {
            let t = String::from_utf8_lossy(&o.stdout);
            let v: Vec<String> = t.lines().filter_map(|l| l.trim().strip_prefix("DriverDesc").map(|r| r.trim().trim_start_matches("REG_SZ").trim().to_string())).filter(|x| !x.is_empty()).collect();
            if !v.is_empty() { return v.join("; "); }
        }
        "unknown".into()
    }
    #[cfg(not(windows))]
    { "n/a".into() }
}
