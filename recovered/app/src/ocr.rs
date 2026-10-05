//! PaddleOCR (PP-OCR detector + English recognizer) on ONNX Runtime. DirectML GPU first, CPU fallback.
//! Input shapes are fixed (one detector canvas per orientation, four recognizer widths, fixed batch on the GPU) so DirectML compiles each shape once.
use ort::session::Session;
use ort::value::Tensor;
use std::path::Path;
use std::sync::Mutex;
use std::collections::HashMap;
use std::time::Instant;

pub struct Word { pub text: String, pub x: f32, pub y: f32, pub w: f32, pub h: f32 }

pub static STAGE: Mutex<String> = Mutex::new(String::new());
pub static HOOK: std::sync::OnceLock<fn(&str)> = std::sync::OnceLock::new();
pub fn stage(s: &str) {
    if let Ok(mut g) = STAGE.lock() { *g = s.to_string(); }
    if let Some(h) = HOOK.get() { h(s); }
}

const REC_BATCH: usize = 8;
const FIXED_WIDTHS: [usize; 3] = [320, 800, 1280];
const FREE_WIDTHS: [usize; 4] = [320, 640, 960, 1280];

pub static INFO: std::sync::OnceLock<fn(&str)> = std::sync::OnceLock::new();
pub fn info(s: &str) { if let Some(h) = INFO.get() { h(s); } }

/// Detector canvas: longest side (multiple of 32). PaddleOCR defaults to 960; 1216 is its example for larger input.
fn default_rows(bucket: usize) -> usize {
    let v: Vec<usize> = std::env::var("LITEPDF_ROWS").unwrap_or_default().split(',').filter_map(|x| x.trim().parse().ok()).collect();
    let i = match bucket { 320 => 0, 800 => 1, _ => 2 };
    if v.len() == 3 && v[i] >= 1 { return v[i]; }
    match bucket { 320 => 64, 800 => 32, _ => 8 }
}
fn det_long() -> usize { std::env::var("LITEPDF_DET").ok().and_then(|v| v.parse::<usize>().ok()).filter(|v| (320..=2048).contains(v)).map(|v| v / 32 * 32).unwrap_or(1216) }
fn det_canvas(portrait: bool) -> (usize, usize) { let l = det_long(); let sh = ((l as f32 * 0.7071) as usize / 32 * 32).max(32); if portrait { (sh, l) } else { (l, sh) } } // (w, h)

#[derive(Default, Clone)]
pub struct Tm { pub det_prep: f32, pub det_run: f32, pub det_post: f32, pub rec_prep: f32, pub rec_run: f32, pub decode: f32, pub sess: f32, pub calls: u32, pub rows_real: u32, pub rows_pad: u32 }
impl Tm { pub fn line(&self) -> String { format!("det prep {:.0} ms, det run {:.0} ms, boxes {:.0} ms, rec prep {:.0} ms, rec run {:.0} ms ({} calls, {} of {} rows used), decode {:.0} ms, session creation {:.0} ms", self.det_prep, self.det_run, self.det_post, self.rec_prep, self.rec_run, self.calls, self.rows_real, self.rows_pad, self.decode, self.sess) } }

pub struct Engine { dir: std::path::PathBuf, threads: usize, gpu: bool, fixed: bool, det_d: Option<Session>, rec_d: Option<Session>, dets: HashMap<(usize, usize), Session>, recs: HashMap<usize, Session>, rows_map: HashMap<usize, usize>, dict: Vec<String>, pub provider: String, pub note: String, pub tm: Tm }

static INIT: std::sync::Once = std::sync::Once::new();
static INIT_ERR: Mutex<Option<String>> = Mutex::new(None);

fn ort_init(dll: &Path) -> Result<(), String> {
    INIT.call_once(|| {
        #[cfg(windows)]
        let pre: Option<String> = {
            use std::os::windows::ffi::OsStrExt;
            extern "system" { fn LoadLibraryW(p: *const u16) -> *mut core::ffi::c_void; fn GetLastError() -> u32; }
            let w: Vec<u16> = dll.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
            if dll.exists() && unsafe { LoadLibraryW(w.as_ptr()) }.is_null() { Some(format!("Windows could not load it (error {}). The Microsoft Visual C++ runtime or DirectML.dll may be missing", unsafe { GetLastError() })) } else { None }
        };
        #[cfg(not(windows))]
        let pre: Option<String> = None;
        let e = if pre.is_some() { pre } else if !dll.exists() { Some("file not found".to_string()) } else { ort::init_from(dll.to_string_lossy().to_string()).commit(); None };
        if let Ok(mut g) = INIT_ERR.lock() { *g = e; }
    });
    let e = INIT_ERR.lock().map(|g| g.clone()).unwrap_or(None);
    match e { Some(e) => Err(format!("onnxruntime load failed ({}): {e}", dll.display())), None => Ok(()) }
}

fn build_session(model: &Path, gpu: bool, threads: usize, dims: &[(&str, i64)]) -> Result<Session, String> {
    let mut b = Session::builder().map_err(|e| e.to_string())?;
    for (n, v) in dims { b = b.with_dimension_override(*n, *v).map_err(|e| e.to_string())?; }
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
        stage("load onnxruntime");
        ort_init(dll)?;
        let dict_txt = std::fs::read_to_string(dir.join("dict.txt")).map_err(|e| format!("dict.txt: {e}"))?;
        let mut dict: Vec<String> = dict_txt.split('\n').map(|s| s.trim_end_matches('\r').to_string()).collect();
        if dict.last().map(|s| s.is_empty()).unwrap_or(false) { dict.pop(); }
        let threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(2).max(1);
        let mut note = String::new();
        let force_fixed = std::env::var("LITEPDF_FIXED").map(|v| v == "1").unwrap_or(false);
        let mut e = Engine { dir: dir.to_path_buf(), threads, gpu: false, fixed: false, det_d: None, rec_d: None, dets: HashMap::new(), recs: HashMap::new(), rows_map: HashMap::new(), dict, provider: String::new(), note: String::new(), tm: Tm::default() };
        if want_gpu {
            // sessions with fixed shapes are created lazily (see det_session / rec_session); check DirectML works now with a tiny probe
            stage("check DirectML");
            match build_session(&dir.join("rec.onnx"), true, threads, &[("DynamicDimension.0", 1), ("DynamicDimension.1", 320)]) {
                Ok(s) => { drop(s); info("GPU recognizer batch sizes: 320 px x64, 800 px x32, 1280 px x8 lines per call (halved automatically if the GPU fails a batch, e.g. out of video memory); detector 1 page per call, canvas long side set by LITEPDF_DET (default 1216)"); e.gpu = true; e.fixed = true; e.provider = "DirectML (GPU)".into(); return Ok(e); }
                Err(er) => note = format!("GPU start failed, using CPU: {er}"),
            }
        }
        stage("create CPU sessions");
        e.fixed = force_fixed; e.note = note;
        if !force_fixed { e.det_d = Some(build_session(&dir.join("det.onnx"), false, threads, &[])?); e.rec_d = Some(build_session(&dir.join("rec.onnx"), false, threads, &[])?); }
        e.provider = format!("CPU ({threads} threads)");
        Ok(e)
    }

    fn widths(&self) -> &'static [usize] { if self.fixed { &FIXED_WIDTHS } else { &FREE_WIDTHS } }
    fn rows_for(&self, bucket: usize) -> usize { if !self.fixed { REC_BATCH } else { self.rows_map.get(&bucket).copied().unwrap_or_else(|| default_rows(bucket)) } }

    fn run_det(&mut self, cw: usize, ch: usize, data: Vec<f32>) -> Result<(Vec<i64>, Vec<f32>), String> {
        if !self.fixed && self.det_d.is_some() {} else if !self.dets.contains_key(&(cw, ch)) {
            stage(&format!("create detector session {cw}x{ch}")); let t = Instant::now();
            let s = build_session(&self.dir.join("det.onnx"), self.gpu, self.threads, &[("DynamicDimension.0", 1), ("DynamicDimension.1", ch as i64), ("DynamicDimension.2", cw as i64)])?;
            let ms = t.elapsed().as_secs_f32() * 1000.0; self.tm.sess += ms; info(&format!("created detector session {cw}x{ch} in {ms:.0} ms"));
            self.dets.insert((cw, ch), s);
        }
        let t = Tensor::from_array(([1usize, 3, ch, cw], data)).map_err(|e| e.to_string())?;
        let t0 = Instant::now();
        let sess = if self.fixed { self.dets.get_mut(&(cw, ch)).ok_or("no detector session")? } else { self.det_d.as_mut().ok_or("no detector session")? };
        let out = sess.run(ort::inputs!["x" => t]).map_err(|e| format!("detector: {e}"))?;
        let (shape, prob) = out[0].try_extract_tensor::<f32>().map_err(|e| e.to_string())?;
        let r = (shape.iter().copied().collect::<Vec<i64>>(), prob.to_vec());
        self.tm.det_run += t0.elapsed().as_secs_f32() * 1000.0;
        Ok(r)
    }

    /// Runs one recognizer batch. If a GPU run fails (for example out of video memory) the batch is halved: a smaller session replaces the big one and stays in use.
    fn run_rec(&mut self, bucket: usize, rows: usize, data: Vec<f32>) -> Result<(Vec<i64>, Vec<f32>), String> {
        match self.run_rec_once(bucket, rows, data.clone()) {
            Ok(r) => Ok(r),
            Err(e) if (self.gpu || std::env::var("LITEPDF_FORCEFAIL").is_ok()) && rows >= 8 => {
                info(&format!("recognizer batch {rows}x48x{bucket} failed on the GPU ({}), halving the batch to {}", e.replace('\n', " "), rows / 2));
                self.recs.remove(&bucket); self.rows_map.insert(bucket, rows / 2);
                let per = rows / 2 * 3 * 48 * bucket;
                let a = self.run_rec(bucket, rows / 2, data[..per].to_vec())?; let b = self.run_rec(bucket, rows / 2, data[per..].to_vec())?;
                let mut shape = a.0.clone(); if !shape.is_empty() { shape[0] = rows as i64; }
                let mut v = a.1; v.extend(b.1); Ok((shape, v))
            }
            Err(e) => Err(e),
        }
    }

    fn run_rec_once(&mut self, bucket: usize, rows: usize, data: Vec<f32>) -> Result<(Vec<i64>, Vec<f32>), String> {
        if self.fixed && !self.recs.contains_key(&bucket) {
            stage(&format!("create recognizer session {rows}x48x{bucket}")); let t = Instant::now();
            let s = build_session(&self.dir.join("rec.onnx"), self.gpu, self.threads, &[("DynamicDimension.0", rows as i64), ("DynamicDimension.1", bucket as i64)])?;
            let ms = t.elapsed().as_secs_f32() * 1000.0; self.tm.sess += ms; info(&format!("created recognizer session {rows}x48x{bucket} in {ms:.0} ms"));
            self.recs.insert(bucket, s);
        }
        if rows >= 32 && std::env::var("LITEPDF_FORCEFAIL").is_ok() { return Err("forced test failure".into()); }
        let t = Tensor::from_array(([rows, 3usize, 48, bucket], data)).map_err(|e| e.to_string())?;
        let t0 = Instant::now();
        let sess = if self.fixed { self.recs.get_mut(&bucket).ok_or("no recognizer session")? } else { self.rec_d.as_mut().ok_or("no recognizer session")? };
        let out = sess.run(ort::inputs!["x" => t]).map_err(|e| format!("recognizer: {e}"))?;
        let (shape, lg) = out[0].try_extract_tensor::<f32>().map_err(|e| e.to_string())?;
        let r = (shape.iter().copied().collect::<Vec<i64>>(), lg.to_vec());
        self.tm.rec_run += t0.elapsed().as_secs_f32() * 1000.0; self.tm.calls += 1;
        Ok(r)
    }

    /// Sessions for fixed shapes are created on first use, so there is nothing to warm up front.
    pub fn warm_up(&mut self) -> Result<(), String> { Ok(()) }

    pub fn recognize(&mut self, rgb: &[u8], w: usize, h: usize) -> Result<Vec<Word>, String> {
        if w < 8 || h < 8 || rgb.len() < w * h * 3 { return Err(format!("bad image size {w}x{h}")); }
        let (boxes, scale) = self.detect(rgb, w, h)?;
        self.read(rgb, w, h, &boxes, scale)
    }

    fn detect(&mut self, rgb: &[u8], w: usize, h: usize) -> Result<(Vec<[f32; 4]>, f32), String> {
        let tp = Instant::now(); let (cw, ch) = det_canvas(h >= w);
        let r = (cw as f32 / w as f32).min(ch as f32 / h as f32).min(1.0);
        let (nw, nh) = (((w as f32 * r) as usize).clamp(1, cw), ((h as f32 * r) as usize).clamp(1, ch));
        stage(&format!("detect {w}x{h} -> canvas {cw}x{ch}"));
        let mean = [0.485f32, 0.456, 0.406]; let std = [0.229f32, 0.224, 0.225];
        let mut data = vec![0f32; 3 * ch * cw];
        for c in 0..3 { let white = (1.0 - mean[c]) / std[c]; for v in &mut data[c * ch * cw..(c + 1) * ch * cw] { *v = white; } }
        for y in 0..nh { for x in 0..nw {
            let px = bilinear(rgb, w, h, (x as f32 + 0.5) / r - 0.5, (y as f32 + 0.5) / r - 0.5);
            // BGR channel order, as PaddleOCR feeds cv2 images
            for c in 0..3 { data[c * ch * cw + y * cw + x] = (px[2 - c] / 255.0 - mean[c]) / std[c]; }
        } }
        self.tm.det_prep += tp.elapsed().as_secs_f32() * 1000.0;
        let (shape, prob) = self.run_det(cw, ch, data)?; let tq = Instant::now();
        if shape.len() < 2 { return Err("detector output shape".into()); }
        let (oh, ow) = (shape[shape.len() - 2] as usize, shape[shape.len() - 1] as usize);
        if oh == 0 || ow == 0 || prob.len() < oh * ow { return Err("detector output too small".into()); }
        stage("detect: find text boxes");
        let mut seen = vec![false; oh * ow]; let mut boxes = vec![]; let mut stack: Vec<u32> = vec![];
        for s in 0..oh * ow {
            if seen[s] || !(prob[s] > 0.3) { continue; }
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
            let d = bw * bh * 1.5 / (2.0 * (bw + bh)); // unclip
            let sx = cw as f32 / ow as f32 / r; let sy = ch as f32 / oh as f32 / r;
            let bx0 = ((x0 as f32 - d) * sx).max(0.0); let by0 = ((y0 as f32 - d) * sy).max(0.0);
            let bx1 = (((x1 + 1) as f32 + d) * sx).min(w as f32); let by1 = (((y1 + 1) as f32 + d) * sy).min(h as f32);
            if bx1 - bx0 >= 4.0 && by1 - by0 >= 4.0 { boxes.push([bx0, by0, bx1, by1]); }
        }
        if boxes.len() > 1500 { boxes.truncate(1500); }
        boxes.sort_by(|a, b| a[1].total_cmp(&b[1]));
        { let mut i = 0; while i < boxes.len() { let (y0, hh) = (boxes[i][1], boxes[i][3] - boxes[i][1]); let mut j = i + 1; while j < boxes.len() && (boxes[j][1] - y0).abs() < hh * 0.5 { j += 1; } boxes[i..j].sort_by(|a, b| a[0].total_cmp(&b[0])); i = j; } }
        self.tm.det_post += tq.elapsed().as_secs_f32() * 1000.0;
        Ok((boxes, r))
    }

    fn read(&mut self, rgb: &[u8], w: usize, h: usize, boxes: &[[f32; 4]], _scale: f32) -> Result<Vec<Word>, String> {
        // pieces: (box index, x offset in the 48-high crop, piece width); long lines are cut at low-ink columns
        let (p0, r0) = (self.tm.rec_prep, self.tm.rec_run); let widths = self.widths(); let maxw = widths[widths.len() - 1]; let tr = Instant::now();
        let mut pieces: Vec<(usize, usize, usize)> = vec![];
        for (i, b) in boxes.iter().enumerate() {
            let sc = 48.0 / (b[3] - b[1]).max(1.0);
            let full = (((b[2] - b[0]) * sc).ceil() as usize).max(8);
            if full <= maxw { pieces.push((i, 0, full)); continue; }
            // ink per column of the 48-high crop
            let mut ink = vec![0f32; full];
            for x in 0..full { let (mut lo, mut hi) = (255f32, 0f32);
                for y in (0..48).step_by(4) { let p = bilinear(rgb, w, h, b[0] + (x as f32 + 0.5) / sc, b[1] + (y as f32 + 0.5) / sc); let l = p[0] * 0.3 + p[1] * 0.59 + p[2] * 0.11; lo = lo.min(l); hi = hi.max(l); }
                ink[x] = hi - lo; }
            let mut x0 = 0usize;
            while full - x0 > maxw {
                let target = x0 + maxw - 80; let (a, z) = (target.saturating_sub(160).max(x0 + 200), (target + 70).min(x0 + maxw).min(full - 1));
                let mut best = target.min(full - 1); let mut bv = f32::MAX;
                for x in a..=z.max(a) { if x < full && ink[x] < bv { bv = ink[x]; best = x; } }
                pieces.push((i, x0, best - x0)); x0 = best;
            }
            pieces.push((i, x0, full - x0));
        }
        let mut words = vec![]; let nclass = self.dict.len();
        for (bi_w, &bucket) in widths.iter().enumerate() {
            let lo = if bi_w == 0 { 0 } else { widths[bi_w - 1] };
            let mut group: Vec<(usize, usize, usize)> = pieces.iter().cloned().filter(|p| p.2 > lo && p.2 <= bucket || (bi_w == 0 && p.2 <= bucket)).collect();
            group.sort_by_key(|p| p.2);
            let cap = self.rows_for(bucket);
            for chunk in group.chunks(cap) {
                let n = chunk.len(); let rows = if self.fixed { cap } else { n }; self.tm.rows_real += n as u32; self.tm.rows_pad += rows as u32;
                let tprep = Instant::now();
                stage(&format!("recognize batch shape [{rows},3,48,{bucket}] ({n} lines)"));
                let mut data = vec![0f32; rows * 3 * 48 * bucket];
                for (k, &(bi, off, pw)) in chunk.iter().enumerate() {
                    let b = boxes[bi]; let sc = 48.0 / (b[3] - b[1]).max(1.0);
                    for y in 0..48 { for x in 0..pw.min(bucket) {
                        let px = bilinear(rgb, w, h, b[0] + ((off + x) as f32 + 0.5) / sc - 0.5, b[1] + (y as f32 + 0.5) / sc - 0.5);
                        for c in 0..3 { data[((k * 3 + c) * 48 + y) * bucket + x] = (px[2 - c] / 255.0 - 0.5) / 0.5; }
                    } }
                }
                self.tm.rec_prep += tprep.elapsed().as_secs_f32() * 1000.0;
                let (shape, lg) = self.run_rec(bucket, rows, data)?; let td = Instant::now();
                if shape.len() < 3 { return Err("recognizer output shape".into()); }
                let (tn, tc) = (shape[1] as usize, shape[2] as usize);
                if tc != nclass { return Err(format!("recognizer has {tc} classes but dictionary has {nclass}")); }
                if lg.len() < rows * tn * tc || tn == 0 { return Err("recognizer output too small".into()); }
                for (k, &(bi, off, _pw)) in chunk.iter().enumerate() {
                    let b = boxes[bi]; let sc = 48.0 / (b[3] - b[1]).max(1.0); let bhei = b[3] - b[1];
                    let step_px = bucket as f32 / tn as f32;
                    let mut chars: Vec<(String, usize, f32)> = vec![]; let mut last = 0usize;
                    for s in 0..tn {
                        let row = &lg[(k * tn + s) * tc..(k * tn + s + 1) * tc];
                        let (mut bi2, mut bv) = (0usize, f32::MIN);
                        for (c, v) in row.iter().enumerate() { if *v > bv { bv = *v; bi2 = c; } }
                        if bi2 != 0 && bi2 != last { chars.push((self.dict[bi2].clone(), s, bv)); }
                        last = bi2;
                    }
                    if chars.is_empty() { continue; }
                    let conf = chars.iter().map(|c| c.2).sum::<f32>() / chars.len() as f32;
                    if !(conf >= 0.45) { continue; }
                    let mut cur: Vec<(String, usize)> = vec![];
                    let flush = |cur: &mut Vec<(String, usize)>, words: &mut Vec<Word>| {
                        if cur.is_empty() { return; }
                        let text: String = cur.iter().map(|c| c.0.as_str()).collect();
                        let s0 = off as f32 + cur[0].1 as f32 * step_px - 10.0; let s1 = off as f32 + (cur[cur.len() - 1].1 as f32 + 1.0) * step_px + 10.0;
                        let x0 = (b[0] + s0 / sc).max(b[0]); let x1 = (b[0] + s1 / sc).min(b[2]);
                        if x1 > x0 { words.push(Word { text, x: x0, y: b[1], w: x1 - x0, h: bhei }); }
                        cur.clear();
                    };
                    for (ch, s, _) in &chars {
                        if ch.trim().is_empty() { flush(&mut cur, &mut words); continue; }
                        cur.push((ch.clone(), *s));
                    }
                    flush(&mut cur, &mut words);
                }
            }
        }
        words.sort_by(|a, b| a.y.total_cmp(&b.y));
        { let mut i = 0; while i < words.len() { let (y0, hh) = (words[i].y, words[i].h); let mut j = i + 1; while j < words.len() && (words[j].y - y0).abs() < hh * 0.5 { j += 1; } words[i..j].sort_by(|a, b| a.x.total_cmp(&b.x)); i = j; } }
        self.tm.decode += tr.elapsed().as_secs_f32() * 1000.0 - (self.tm.rec_prep - p0) - (self.tm.rec_run - r0);
        Ok(words)
    }
    pub fn take_timing(&mut self) -> Tm { std::mem::take(&mut self.tm) }
}

fn bilinear(rgb: &[u8], w: usize, h: usize, x: f32, y: f32) -> [f32; 3] {
    if w == 0 || h == 0 { return [255.0; 3]; }
    let x = if x.is_nan() { 0.0 } else { x.clamp(0.0, (w - 1) as f32) }; let y = if y.is_nan() { 0.0 } else { y.clamp(0.0, (h - 1) as f32) };
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
