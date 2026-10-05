mkdir -p /tmp/scratch/app/src && cat > /tmp/scratch/app/src/ocr.rs <<'EOF'
//! PaddleOCR (PP-OCR detector + English recognizer) on ONNX Runtime. DirectML GPU first, CPU fallback.
use ort::session::Session;
use ort::value::Tensor;
use std::path::Path;

pub struct Word { pub text: String, pub x: f32, pub y: f32, pub w: f32, pub h: f32 }

pub struct Engine { det: Session, rec: Session, dict: Vec<String>, pub provider: String, pub note: String }

static INIT: std::sync::Once = std::sync::Once::new();
static INIT_ERR: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);

fn ort_init(dll: &Path) -> Result<(), String> {
    INIT.call_once(|| {
        let r = std::panic::catch_unwind(|| ort::init_from(dll.to_string_lossy().to_string()).map(|b| { b.commit(); }).map_err(|e| e.to_string()));
        let e = match r { Ok(Ok(())) => None, Ok(Err(e)) => Some(e), Err(_) => Some("could not load onnxruntime".into()) };
        *INIT_ERR.lock().unwrap() = e;
    });
    match INIT_ERR.lock().unwrap().clone() { Some(e) => Err(format!("onnxruntime load failed ({}): {e}", dll.display())), None => Ok(()) }
}

fn build_session(model: &Path, gpu: bool, threads: usize) -> Result<Session, String> {
    let mut b = Session::builder().map_err(|e| e.to_string())?;
    if gpu {
        use ort::execution_providers::DirectMLExecutionProvider;
        b = b.with_execution_providers([DirectMLExecutionProvider::default().build().error_on_failure()]).map_err(|e| format!("DirectML unavailable: {e}"))?;
        b = b.with_memory_pattern(false).map_err(|e| e.to_string())?;
        b = b.with_parallel_execution(false).map_err(|e| e.to_string())?;
    } else {
        b = b.with_intra_threads(threads).map_err(|e| e.to_string())?;
    }
    b.commit_from_file(model).map_err(|e| format!("{}: {e}", model.display()))
}

impl Engine {
    /// dir holds det.onnx, rec.onnx, dict.txt. dll is the full path to onnxruntime.dll / libonnxruntime.so.
    pub fn new(dir: &Path, dll: &Path, want_gpu: bool) -> Result<Engine, String> {
        ort_init(dll)?;
        let dict_txt = std::fs::read_to_string(dir.join("dict.txt")).map_err(|e| format!("dict.txt: {e}"))?;
        let dict: Vec<String> = dict_txt.split('\n').map(|s| s.trim_end_matches('\r').to_string()).collect::<Vec<_>>();
        let dict = if dict.last().map(|s| s.is_empty()).unwrap_or(false) { dict[..dict.len() - 1].to_vec() } else { dict };
        let threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(2).max(1);
        let mut note = String::new();
        if want_gpu {
            let r = (|| -> Result<(Session, Session), String> { Ok((build_session(&dir.join("det.onnx"), true, threads)?, build_session(&dir.join("rec.onnx"), true, threads)?)) })();
            match r { Ok((det, rec)) => return Ok(Engine { det, rec, dict, provider: "DirectML (GPU)".into(), note }), Err(e) => note = format!("GPU start failed, using CPU: {e}") }
        }
        let det = build_session(&dir.join("det.onnx"), false, threads)?;
        let rec = build_session(&dir.join("rec.onnx"), false, threads)?;
        Ok(Engine { det, rec, dict, provider: format!("CPU ({threads} threads)"), note })
    }

    pub fn recognize(&mut self, rgb: &[u8], w: usize, h: usize) -> Result<Vec<Word>, String> {
        let boxes = self.detect(rgb, w, h)?;
        self.read(rgb, w, h, &boxes)
    }

    fn detect(&mut self, rgb: &[u8], w: usize, h: usize) -> Result<Vec<[f32; 4]>, String> {
        let limit = 1536.0f32;
        let r = (limit / w.max(h) as f32).min(1.0);
        let rw = (((w as f32 * r) / 32.0).round() as usize).max(1) * 32;
        let rh = (((h as f32 * r) / 32.0).round() as usize).max(1) * 32;
        let mean = [0.485f32, 0.456, 0.406]; let std = [0.229f32, 0.224, 0.225];
        let mut data = vec![0f32; 3 * rh * rw];
        for y in 0..rh { for x in 0..rw {
            let px = bilinear(rgb, w, h, (x as f32 + 0.5) * w as f32 / rw as f32 - 0.5, (y as f32 + 0.5) * h as f32 / rh as f32 - 0.5);
            // BGR channel order, as PaddleOCR feeds cv2 images
            for c in 0..3 { data[c * rh * rw + y * rw + x] = (px[2 - c] / 255.0 - mean[c]) / std[c]; }
        } }
        let t = Tensor::from_array(([1usize, 3, rh, rw], data)).map_err(|e| e.to_string())?;
        let out = self.det.run(ort::inputs!["x" => t]).map_err(|e| format!("detector: {e}"))?;
        let (shape, prob) = out[0].try_extract_tensor::<f32>().map_err(|e| e.to_string())?;
        let (oh, ow) = (shape[shape.len() - 2] as usize, shape[shape.len() - 1] as usize);
        if prob.len() < oh * ow { return Err("detector output too small".into()); }
        // connected components on prob > 0.3
        let mut seen = vec![false; oh * ow]; let mut boxes = vec![]; let mut stack: Vec<u32> = vec![];
        for s in 0..oh * ow {
            if seen[s] || prob[s] <= 0.3 { continue; }
            seen[s] = true; stack.push(s as u32);
            let (mut x0, mut y0, mut x1, mut y1) = (ow, oh, 0usize, 0usize); let (mut cnt, mut sum) = (0u32, 0f32);
            while let Some(p) = stack.pop() {
                let p = p as usize; let (px, py) = (p % ow, p / ow);
                x0 = x0.min(px); x1 = x1.max(px); y0 = y0.min(py); y1 = y1.max(py); cnt += 1; sum += prob[p];
                for (dx, dy) in [(-1i32, 0i32), (1, 0), (0, -1), (0, 1)] {
                    let (nx, ny) = (px as i32 + dx, py as i32 + dy);
                    if nx < 0 || ny < 0 || nx >= ow as i32 || ny >= oh as i32 { continue; }
                    let n = ny as usize * ow + nx as usize;
                    if !seen[n] && prob[n] > 0.3 { seen[n] = true; stack.push(n as u32); }
                }
            }
            let (bw, bh) = ((x1 - x0 + 1) as f32, (y1 - y0 + 1) as f32);
            if bw < 3.0 || bh < 3.0 || cnt < 12 || sum / (cnt as f32) < 0.55 { continue; }
            // unclip (DB shrinks text areas; ratio 1.5)
            let d = bw * bh * 1.5 / (2.0 * (bw + bh));
            let sx = w as f32 / ow as f32; let sy = h as f32 / oh as f32;
            let bx0 = ((x0 as f32 - d) * sx).max(0.0); let by0 = ((y0 as f32 - d) * sy).max(0.0);
            let bx1 = (((x1 + 1) as f32 + d) * sx).min(w as f32); let by1 = (((y1 + 1) as f32 + d) * sy).min(h as f32);
            if bx1 - bx0 >= 4.0 && by1 - by0 >= 4.0 { boxes.push([bx0, by0, bx1, by1]); }
        }
        boxes.sort_by(|a, b| { let ha = a[3] - a[1]; if (a[1] - b[1]).abs() < ha * 0.5 { a[0].partial_cmp(&b[0]).unwrap() } else { a[1].partial_cmp(&b[1]).unwrap() } });
        Ok(boxes)
    }

    fn read(&mut self, rgb: &[u8], w: usize, h: usize, boxes: &[[f32; 4]]) -> Result<Vec<Word>, String> {
        // crop widths at height 48
        let mut items: Vec<(usize, usize)> = boxes.iter().enumerate().map(|(i, b)| {
            let r = (b[2] - b[0]) / (b[3] - b[1]).max(1.0); (i, ((48.0 * r).ceil() as usize).clamp(16, 4000)) }).collect();
        items.sort_by_key(|x| x.1);
        let mut words = vec![]; let nclass = self.dict.len() + 1;
        let mut i = 0;
        while i < items.len() {
            let mut j = i; let mut maxw = 0;
            while j < items.len() && j - i < 12 { maxw = maxw.max(items[j].1); j += 1; if maxw > 1600 { break; } }
            let bw = (maxw + 31) / 32 * 32; let n = j - i;
            let mut data = vec![0f32; n * 3 * 48 * bw];
            for (k, &(bi, cw)) in items[i..j].iter().enumerate() {
                let b = boxes[bi]; let (bwid, bhei) = (b[2] - b[0], b[3] - b[1]);
                for y in 0..48 { for x in 0..cw {
                    let sx = b[0] + (x as f32 + 0.5) * bwid / cw as f32 - 0.5; let sy = b[1] + (y as f32 + 0.5) * bhei / 48.0 - 0.5;
                    let px = bilinear(rgb, w, h, sx, sy);
                    for c in 0..3 { data[((k * 3 + c) * 48 + y) * bw + x] = (px[2 - c] / 255.0 - 0.5) / 0.5; }
                } }
            }
            let t = Tensor::from_array(([n, 3usize, 48, bw], data)).map_err(|e| e.to_string())?;
            let out = self.rec.run(ort::inputs!["x" => t]).map_err(|e| format!("recognizer: {e}"))?;
            let (shape, lg) = out[0].try_extract_tensor::<f32>().map_err(|e| e.to_string())?;
            let (tn, tc) = (shape[1] as usize, shape[2] as usize);
            if tc != nclass { return Err(format!("recognizer has {tc} classes but dictionary has {}", self.dict.len())); }
            for (k, &(bi, cw)) in items[i..j].iter().enumerate() {
                let b = boxes[bi]; let bwid = b[2] - b[0]; let bhei = b[3] - b[1];
                let step_px = bw as f32 / tn as f32;           // px in the 48-high padded crop
                let to_page = bwid / cw as f32;                // crop px -> page px
                // greedy CTC
                let mut chars: Vec<(String, usize, f32)> = vec![]; let mut last = 0usize;
                for s in 0..tn {
                    let row = &lg[(k * tn + s) * tc..(k * tn + s + 1) * tc];
                    let (mut bi2, mut bv) = (0usize, f32::MIN);
                    for (c, v) in row.iter().enumerate() { if *v > bv { bv = *v; bi2 = c; } }
                    if bi2 != 0 && bi2 != last { chars.push((self.dict[bi2 - 1].clone(), s, bv)); }
                    last = bi2;
                }
                if chars.is_empty() { continue; }
                let conf = chars.iter().map(|c| c.2).sum::<f32>() / chars.len() as f32;
                if conf < 0.45 { continue; }
                // group into words: split on space chars or a wide gap between characters
                let mut cur: Vec<(String, usize)> = vec![];
                let mut flush = |cur: &mut Vec<(String, usize)>, words: &mut Vec<Word>| {
                    if cur.is_empty() { return; }
                    let text: String = cur.iter().map(|c| c.0.as_str()).collect();
                    let s0 = cur[0].1 as f32 * step_px; let s1 = (cur[cur.len() - 1].1 as f32 + 1.0) * step_px;
                    let x0 = (b[0] + s0 * to_page).max(b[0]); let x1 = (b[0] + s1 * to_page).min(b[2]);
                    if x1 > x0 { words.push(Word { text, x: x0, y: b[1], w: x1 - x0, h: bhei }); }
                    cur.clear();
                };
                let mut prev_s: Option<usize> = None;
                for (ch, s, _) in &chars {
                    if ch.trim().is_empty() { flush(&mut cur, &mut words); prev_s = None; continue; }
                    if let Some(p) = prev_s { if (*s - p) as f32 * step_px > 20.0 { flush(&mut cur, &mut words); } }
                    cur.push((ch.clone(), *s)); prev_s = Some(*s);
                }
                flush(&mut cur, &mut words);
            }
            i = j;
        }
        words.sort_by(|a, b| { let ha = a.h; if (a.y - b.y).abs() < ha * 0.5 { a.x.partial_cmp(&b.x).unwrap() } else { a.y.partial_cmp(&b.y).unwrap() } });
        Ok(words)
    }
}

fn bilinear(rgb: &[u8], w: usize, h: usize, x: f32, y: f32) -> [f32; 3] {
    let x = x.clamp(0.0, (w - 1) as f32); let y = y.clamp(0.0, (h - 1) as f32);
    let (x0, y0) = (x as usize, y as usize); let (x1, y1) = ((x0 + 1).min(w - 1), (y0 + 1).min(h - 1));
    let (fx, fy) = (x - x0 as f32, y - y0 as f32);
    let mut o = [0f32; 3];
    for c in 0..3 {
        let a = rgb[(y0 * w + x0) * 3 + c] as f32; let b = rgb[(y0 * w + x1) * 3 + c] as f32;
        let d = rgb[(y1 * w + x0) * 3 + c] as f32; let e = rgb[(y1 * w + x1) * 3 + c] as f32;
        o[c] = (a * (1.0 - fx) + b * fx) * (1.0 - fy) + (d * (1.0 - fx) + e * fx) * fy;
    }
    o
}
EOF
cd /tmp/scratch/shot; cat src/bin/ocrtest.rs | head -30; ls target | head
