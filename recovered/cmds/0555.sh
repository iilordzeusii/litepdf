cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
def rep(a,b):
    global s
    assert a in s, a[:70]
    s=s.replace(a,b,1)
rep("let (cw, ch) = if h >= w { DET_PORTRAIT } else { DET_LANDSCAPE };","let tp = Instant::now(); let (cw, ch) = det_canvas(h >= w);")
rep(".min(2.0);",".min(1.0);")
rep("""        let t = Tensor::from_array(([1usize, 3, ch, cw], data)).map_err(|e| e.to_string())?;
        let out = self.det.run(ort::inputs!["x" => t]).map_err(|e| format!("detector: {e}"))?;
        let (shape, prob) = out[0].try_extract_tensor::<f32>().map_err(|e| e.to_string())?;""","""        self.tm.det_prep += tp.elapsed().as_secs_f32() * 1000.0;
        let (shape, prob) = self.run_det(cw, ch, data)?; let tq = Instant::now();""")
rep("        Ok((boxes, r))\n","        self.tm.det_post += tq.elapsed().as_secs_f32() * 1000.0;\n        Ok((boxes, r))\n")
rep("let maxw = REC_WIDTHS[REC_WIDTHS.len() - 1];","let widths = self.widths(); let maxw = widths[widths.len() - 1]; let tr = Instant::now();")
rep("for (bi_w, &bucket) in REC_WIDTHS.iter().enumerate() {","for (bi_w, &bucket) in widths.iter().enumerate() {")
rep("let lo = if bi_w == 0 { 0 } else { REC_WIDTHS[bi_w - 1] };","let lo = if bi_w == 0 { 0 } else { widths[bi_w - 1] };")
rep("for chunk in group.chunks(REC_BATCH) {\n                let n = chunk.len(); let rows = if self.fixed { REC_BATCH } else { n };","let cap = self.rows_for(bucket);\n            for chunk in group.chunks(cap) {\n                let n = chunk.len(); let rows = if self.fixed { cap } else { n }; self.tm.rows_real += n as u32; self.tm.rows_pad += rows as u32;\n                let tprep = Instant::now();")
rep("""                let t = Tensor::from_array(([rows, 3usize, 48, bucket], data)).map_err(|e| e.to_string())?;
                let out = self.rec.run(ort::inputs!["x" => t]).map_err(|e| format!("recognizer: {e}"))?;
                let (shape, lg) = out[0].try_extract_tensor::<f32>().map_err(|e| e.to_string())?;""","""                self.tm.rec_prep += tprep.elapsed().as_secs_f32() * 1000.0;
                let (shape, lg) = self.run_rec(bucket, rows, data)?; let td = Instant::now();""")
open('ocr.rs','w').write(s)
E
grep -n "flush(&mut cur, &mut words);$" ocr.rs | tail -2; sed -n 255,262p ocr.rs
