cd /tmp/scratch/app && python3 - <<'EOF'
p='Cargo.toml'; s=open(p).read()
s=s.replace('jpeg-encoder = "0.6"\n','jpeg-encoder = "0.6"\nserde_json = "1"\nunderskrift = { version = "0.1.4", default-features = false, features = ["blocking"] }\nlopdf = "0.39"\ntokio = { version = "1", features = ["rt"] }\n')
open(p,'w').write(s)
EOF
cat > src/extras.rs <<'EOF'
//! Signing, OCR (bundled Tesseract subprocess) and AI (HTTPS via curl, no RAG: text/image goes straight to the provider).
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
pub struct Settings { pub provider: String, pub key: String, pub model: String }
fn settings_path() -> PathBuf {
    let base = std::env::var("APPDATA").or_else(|_| std::env::var("XDG_CONFIG_HOME")).unwrap_or_else(|_| std::env::var("HOME").map(|h| format!("{h}/.config")).unwrap_or_default());
    PathBuf::from(base).join("LitePDF").join("settings.json")
}
pub fn load_settings() -> Settings {
    let mut s = Settings { provider: "Gemini".into(), ..Default::default() };
    if let Ok(t) = std::fs::read_to_string(settings_path()) { if let Ok(v) = serde_json::from_str::<Value>(&t) {
        if let Some(x) = v["provider"].as_str() { s.provider = x.into(); } if let Some(x) = v["key"].as_str() { s.key = x.into(); } if let Some(x) = v["model"].as_str() { s.model = x.into(); } } }
    s
}
pub fn save_settings(s: &Settings) {
    let p = settings_path(); if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
    let _ = std::fs::write(p, json!({"provider": s.provider, "key": s.key, "model": s.model}).to_string());
}

// ---------- AI ----------
pub fn ai_ask(s: &Settings, prompt: &str, page_text: Option<&str>, image_jpeg_b64: Option<&str>) -> Result<String, String> {
    if s.key.trim().is_empty() { return Err("Add your API key first.".into()); }
    if s.model.trim().is_empty() { return Err("Type a model name first.".into()); }
    let mut full = String::new();
    if let Some(t) = page_text { full.push_str("Document text:\n"); full.push_str(t); full.push_str("\n\n"); }
    full.push_str(prompt);
    let gemini = s.provider == "Gemini";
    let (url, header, body) = if gemini {
        let mut parts = vec![json!({"text": full})];
        if let Some(i) = image_jpeg_b64 { parts.push(json!({"inline_data": {"mime_type": "image/jpeg", "data": i}})); }
        (format!("https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent", s.model.trim()), format!("x-goog-api-key: {}", s.key.trim()), json!({"contents": [{"parts": parts}]}))
    } else {
        let mut content = vec![json!({"type": "text", "text": full})];
        if let Some(i) = image_jpeg_b64 { content.push(json!({"type": "image_url", "image_url": {"url": format!("data:image/jpeg;base64,{i}")}})); }
        ("https://openrouter.ai/api/v1/chat/completions".to_string(), format!("Authorization: Bearer {}", s.key.trim()), json!({"model": s.model.trim(), "messages": [{"role": "user", "content": content}]}))
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

// ---------- OCR ----------
fn tess_exe() -> PathBuf { let l = exe_dir().join("ocr").join(if cfg!(windows) { "tesseract.exe" } else { "tesseract" }); if l.exists() { l } else { PathBuf::from("tesseract") } }
pub fn ocr_bmp(bmp: &std::path::Path) -> Result<Vec<crate::ops::OcrWord>, String> {
    let td = exe_dir().join("ocr").join("tessdata");
    let out = std::env::temp_dir().join(format!("litepdf-ocr-{}", std::process::id()));
    let mut c = Command::new(tess_exe()); nowin(&mut c);
    if td.exists() { c.arg("--tessdata-dir").arg(&td); }
    let r = c.arg(bmp).arg(&out).args(["-l", "eng", "--psm", "3", "-c", "tessedit_create_tsv=1"]).output().map_err(|e| format!("OCR engine missing: {e}"))?;
    if !r.status.success() { return Err(String::from_utf8_lossy(&r.stderr).chars().take(300).collect()); }
    let tsv = std::fs::read_to_string(out.with_extension("tsv")).map_err(|e| e.to_string())?;
    let _ = std::fs::remove_file(out.with_extension("tsv"));
    let mut words = vec![];
    for l in tsv.lines().skip(1) {
        let f: Vec<&str> = l.split('\t').collect();
        if f.len() < 12 || f[0] != "5" { continue; }
        let t = f[11].trim(); if t.is_empty() { continue; }
        if let (Ok(x), Ok(y), Ok(w), Ok(h)) = (f[6].parse(), f[7].parse(), f[8].parse(), f[9].parse()) { words.push(crate::ops::OcrWord { text: t.to_string(), x, y, w, h }); }
    }
    Ok(words)
}

/// OCR every page of the doc in place (text layer only, page size unchanged).
pub fn ocr_document(doc: &mut mupdf::pdf::PdfDocument, progress: &mut dyn FnMut(usize, usize)) -> Result<usize, String> {
    use mupdf::{Colorspace, Matrix};
    let n = doc.page_count().map_err(|e| e.to_string())? as usize; let dpi = 300.0f32; let mut total = 0;
    for i in 0..n {
        progress(i, n);
        let pg = doc.load_page(i as i32).map_err(|e| e.to_string())?;
        let s = dpi / 72.0;
        let pm = pg.to_pixmap(&Matrix::new_scale(s, s), &Colorspace::device_rgb(), false, true).map_err(|e| e.to_string())?;
        let bmp = std::env::temp_dir().join(format!("litepdf-ocr-{}-{i}.bmp", std::process::id()));
        write_bmp(&bmp, pm.width() as usize, pm.height() as usize, pm.samples()).map_err(|e| e.to_string())?;
        let words = ocr_bmp(&bmp)?; let _ = std::fs::remove_file(&bmp);
        total += words.len();
        crate::ops::add_text_layer(doc, i as i32, &words, dpi).map_err(|e| e.to_string())?;
    }
    Ok(total)
}
pub fn write_bmp(p: &std::path::Path, w: usize, h: usize, rgb: &[u8]) -> std::io::Result<()> {
    let row = (w * 3 + 3) & !3; let size = 54 + row * h;
    let mut b = Vec::with_capacity(size);
    b.extend_from_slice(b"BM"); b.extend_from_slice(&(size as u32).to_le_bytes()); b.extend_from_slice(&[0; 4]); b.extend_from_slice(&54u32.to_le_bytes());
    b.extend_from_slice(&40u32.to_le_bytes()); b.extend_from_slice(&(w as i32).to_le_bytes()); b.extend_from_slice(&(h as i32).to_le_bytes());
    b.extend_from_slice(&1u16.to_le_bytes()); b.extend_from_slice(&24u16.to_le_bytes()); b.extend_from_slice(&[0; 24]);
    let pad = row - w * 3;
    for y in (0..h).rev() { for x in 0..w { let o = (y * w + x) * 3; b.extend_from_slice(&[rgb[o + 2], rgb[o + 1], rgb[o]]); } b.extend(std::iter::repeat(0).take(pad)); }
    std::fs::write(p, b)
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
EOF
grep -n "enable_all\|tokio" ../sg/Cargo.toml ../sg/src/main.rs | head -3
