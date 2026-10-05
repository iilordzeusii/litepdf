cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
def rep(a,b):
    global s
    assert a in s, a[:70]
    s=s.replace(a,b,1)
rep("recs: HashMap<usize, Session>, dict","recs: HashMap<usize, Session>, rows_map: HashMap<usize, usize>, dict")
rep("recs: HashMap::new(), dict,","recs: HashMap::new(), rows_map: HashMap::new(), dict,")
rep("fn rows_for(&self, bucket: usize) -> usize { if !self.fixed { REC_BATCH } else { match bucket { 320 => 32, 800 => 16, _ => 8 } } }",
"fn rows_for(&self, bucket: usize) -> usize { if !self.fixed { REC_BATCH } else { self.rows_map.get(&bucket).copied().unwrap_or(match bucket { 320 => 64, 800 => 32, _ => 16 }) } }")
rep("    fn run_rec(&mut self, bucket: usize, rows: usize, data: Vec<f32>) -> Result<(Vec<i64>, Vec<f32>), String> {",
"""    /// Runs one recognizer batch. If a GPU run fails (for example out of video memory) the batch is halved: a smaller session replaces the big one and stays in use.
    fn run_rec(&mut self, bucket: usize, rows: usize, data: Vec<f32>) -> Result<(Vec<i64>, Vec<f32>), String> {
        match self.run_rec_once(bucket, rows, data.clone()) {
            Ok(r) => Ok(r),
            Err(e) if self.gpu && rows >= 8 => {
                info(&format!("recognizer batch {rows}x48x{bucket} failed on the GPU ({}), halving the batch to {}", e.replace('\\n', " "), rows / 2));
                self.recs.remove(&bucket); self.rows_map.insert(bucket, rows / 2);
                let per = rows / 2 * 3 * 48 * bucket;
                let a = self.run_rec(bucket, rows / 2, data[..per].to_vec())?; let b = self.run_rec(bucket, rows / 2, data[per..].to_vec())?;
                let mut shape = a.0.clone(); if !shape.is_empty() { shape[0] = rows as i64; }
                let mut v = a.1; v.extend(b.1); Ok((shape, v))
            }
            Err(e) => Err(e),
        }
    }

    fn run_rec_once(&mut self, bucket: usize, rows: usize, data: Vec<f32>) -> Result<(Vec<i64>, Vec<f32>), String> {""")
rep('Ok(s) => { e.recs.insert(320, s); e.gpu = true;','Ok(s) => { drop(s); info("GPU recognizer batch sizes: 320 px x64, 800 px x32, 1280 px x16 lines per call (halved automatically if the GPU fails a batch, e.g. out of video memory); detector 1 page per call, canvas long side set by LITEPDF_DET (default 1216)"); e.gpu = true;')
open('ocr.rs','w').write(s)
E
tail -3 /tmp/runall.out | cut -c1-200
