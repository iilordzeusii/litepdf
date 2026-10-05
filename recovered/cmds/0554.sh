cd /tmp/scratch/app/src; cp ocr.rs /tmp/ocr.rs.bak; cp extras.rs /tmp/extras.rs.bak; cp app.rs /tmp/app.rs.bak; python3 - <<'E'
s=open('ocr.rs').read()
def rep(a,b,cnt=1):
    global s
    assert a in s, a[:60]
    s=s.replace(a,b,cnt)
rep("use std::sync::Mutex;","use std::sync::Mutex;\nuse std::collections::HashMap;\nuse std::time::Instant;")
rep("""const DET_PORTRAIT: (usize, usize) = (1152, 1536); // w, h
const DET_LANDSCAPE: (usize, usize) = (1536, 1152);
const REC_WIDTHS: [usize; 4] = [320, 640, 960, 1280];
const REC_BATCH: usize = 8;

pub struct Engine { det: Session, rec: Session, dict: Vec<String>, pub provider: String, pub note: String, fixed: bool }
""","""const REC_BATCH: usize = 8;
const FIXED_WIDTHS: [usize; 3] = [320, 800, 1280];
const FREE_WIDTHS: [usize; 4] = [320, 640, 960, 1280];

pub static INFO: std::sync::OnceLock<fn(&str)> = std::sync::OnceLock::new();
pub fn info(s: &str) { if let Some(h) = INFO.get() { h(s); } }

/// Detector canvas: longest side (multiple of 32). PaddleOCR defaults to 960; 1216 is its example for larger input.
fn det_long() -> usize { std::env::var("LITEPDF_DET").ok().and_then(|v| v.parse::<usize>().ok()).filter(|v| (320..=2048).contains(v)).map(|v| v / 32 * 32).unwrap_or(1216) }
fn det_canvas(portrait: bool) -> (usize, usize) { let l = det_long(); let sh = ((l as f32 * 0.7071) as usize / 32 * 32).max(32); if portrait { (sh, l) } else { (l, sh) } } // (w, h)

#[derive(Default, Clone)]
pub struct Tm { pub det_prep: f32, pub det_run: f32, pub det_post: f32, pub rec_prep: f32, pub rec_run: f32, pub decode: f32, pub sess: f32, pub calls: u32, pub rows_real: u32, pub rows_pad: u32 }
impl Tm { pub fn line(&self) -> String { format!("det prep {:.0} ms, det run {:.0} ms, boxes {:.0} ms, rec prep {:.0} ms, rec run {:.0} ms ({} calls, {} of {} rows used), decode {:.0} ms, session creation {:.0} ms", self.det_prep, self.det_run, self.det_post, self.rec_prep, self.rec_run, self.calls, self.rows_real, self.rows_pad, self.decode, self.sess) } }

pub struct Engine { dir: std::path::PathBuf, threads: usize, gpu: bool, fixed: bool, det_d: Option<Session>, rec_d: Option<Session>, dets: HashMap<(usize, usize), Session>, recs: HashMap<usize, Session>, dict: Vec<String>, pub provider: String, pub note: String, pub tm: Tm }
""")
rep("""fn build_session(model: &Path, gpu: bool, threads: usize) -> Result<Session, String> {
    let mut b = Session::builder().map_err(|e| e.to_string())?;""","""fn build_session(model: &Path, gpu: bool, threads: usize, dims: &[(&str, i64)]) -> Result<Session, String> {
    let mut b = Session::builder().map_err(|e| e.to_string())?;
    for (n, v) in dims { b = b.with_dimension_override(*n, *v).map_err(|e| e.to_string())?; }""")
# Engine::new body
i=s.index("        let threads = std::thread::available_parallelism()")
j=s.index("    /// Run every fixed shape once")
new_new='''        let threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(2).max(1);
        let mut note = String::new();
        let force_fixed = std::env::var("LITEPDF_FIXED").map(|v| v == "1").unwrap_or(false);
        let mut e = Engine { dir: dir.to_path_buf(), threads, gpu: false, fixed: false, det_d: None, rec_d: None, dets: HashMap::new(), recs: HashMap::new(), dict, provider: String::new(), note: String::new(), tm: Tm::default() };
        if want_gpu {
            // sessions with fixed shapes are created lazily (see det_session / rec_session); check DirectML works now with a tiny probe
            stage("check DirectML");
            match build_session(&dir.join("rec.onnx"), true, threads, &[("DynamicDimension.0", 1), ("DynamicDimension.1", 320)]) {
                Ok(s) => { e.recs.insert(320, s); e.gpu = true; e.fixed = true; e.provider = "DirectML (GPU)".into(); return Ok(e); }
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
    fn rows_for(&self, bucket: usize) -> usize { if !self.fixed { REC_BATCH } else { match bucket { 320 => 32, 800 => 16, _ => 8 } } }

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

    fn run_rec(&mut self, bucket: usize, rows: usize, data: Vec<f32>) -> Result<(Vec<i64>, Vec<f32>), String> {
        if self.fixed && !self.recs.contains_key(&bucket) {
            stage(&format!("create recognizer session {rows}x48x{bucket}")); let t = Instant::now();
            let s = build_session(&self.dir.join("rec.onnx"), self.gpu, self.threads, &[("DynamicDimension.0", rows as i64), ("DynamicDimension.1", bucket as i64)])?;
            let ms = t.elapsed().as_secs_f32() * 1000.0; self.tm.sess += ms; info(&format!("created recognizer session {rows}x48x{bucket} in {ms:.0} ms"));
            self.recs.insert(bucket, s);
        }
        let t = Tensor::from_array(([rows, 3usize, 48, bucket], data)).map_err(|e| e.to_string())?;
        let t0 = Instant::now();
        let sess = if self.fixed { self.recs.get_mut(&bucket).ok_or("no recognizer session")? } else { self.rec_d.as_mut().ok_or("no recognizer session")? };
        let out = sess.run(ort::inputs!["x" => t]).map_err(|e| format!("recognizer: {e}"))?;
        let (shape, lg) = out[0].try_extract_tensor::<f32>().map_err(|e| e.to_string())?;
        let r = (shape.iter().copied().collect::<Vec<i64>>(), lg.to_vec());
        self.tm.rec_run += t0.elapsed().as_secs_f32() * 1000.0; self.tm.calls += 1;
        Ok(r)
    }

'''
s=s[:i]+new_new+s[j:]
# warm_up: no-op now
i=s.index("    /// Run every fixed shape once")
j=s.index("    pub fn recognize(")
s=s[:i]+"    /// Sessions for fixed shapes are created on first use, so there is nothing to warm up front.\n    pub fn warm_up(&mut self) -> Result<(), String> { Ok(()) }\n\n"+s[j:]
open('ocr.rs','w').write(s)
E
grep -n "REC_WIDTHS\|DET_PORTRAIT\|self.det\b\|self.rec\b\|fn detect\|try_extract\|Tensor::from" ocr.rs
