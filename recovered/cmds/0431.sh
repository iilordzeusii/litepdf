cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
s=s.replace("if let Some(p) = prev_s { if (*s - p) as f32 * step_px > 20.0 { flush(&mut cur, &mut words); } }","")
s=s.replace("let s0 = cur[0].1 as f32 * step_px; let s1 = (cur[cur.len() - 1].1 as f32 + 1.0) * step_px;","let s0 = cur[0].1 as f32 * step_px - 10.0; let s1 = (cur[cur.len() - 1].1 as f32 + 1.0) * step_px + 10.0;")
s=s.replace("let mut prev_s: Option<usize> = None;","let mut prev_s: Option<usize> = None; let _ = prev_s;")
open('ocr.rs','w').write(s)
E
cd /tmp/scratch/ocrt; env -i HOME=$HOME PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.cargo/bin bash -c 'source ~/.cargo/env; cargo build --release 2>&1 | grep -E "^error|Finished"'
for f in cover samp; do ./target/release/ocrt /tmp/scratch/$f.raw /tmp/scratch/ocrdl $LD 2>&1 | grep -v "^\x1b" | tail -1 | cut -c1-700; done
