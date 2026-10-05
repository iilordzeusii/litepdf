source /tmp/scratch/wenv.sh; cd /tmp; python3 - <<'PYEOF'
s=open('/tmp/scratch/app/src/app.rs').read()
i=s.index("/// Port of Chromium's cc::ScrollOffsetAnimationCurve")
open('/tmp/sa.rs','w').write(s[i:]+'''
use std::time::{Duration,Instant};
fn main(){
 let t0=Instant::now();
 let mut a=ScrollAnim::new(t0,100.0);
 // first frame 7ms after a notch
 let v=a.value(t0+Duration::from_millis(7)); println!("7ms: {v:.1} of 100"); assert!(v>3.0);
 let mut total=0.0f32; let mut last=0.0f32;
 // 3 more notches at 40ms spacing
 for k in 1..=3 { a.update_target(t0+Duration::from_millis(40*k), 100.0); }
 for ms in (0..=800).step_by(8){ let now=t0+Duration::from_millis(ms); let v=a.value(now); assert!(v>=last-0.01,"non monotonic at {ms}: {v} < {last}"); last=v; total=v; }
 println!("final {total:.2} (expect 400)"); assert!((total-400.0).abs()<0.5);
 // touchpad-like small deltas
 let mut b=ScrollAnim::new(t0,8.0); for k in 1..60 { b.update_target(t0+Duration::from_millis(8*k),8.0); let v=b.value(t0+Duration::from_millis(8*k)); if k%15==0 {println!("tp k={k} v={v:.1} target 8*{}", k+1);} }
 let v=b.value(t0+Duration::from_millis(2000)); println!("tp final {v:.1} (expect 480)"); assert!((v-480.0).abs()<0.5);
 println!("ok"); }
''')
PYEOF
rustc -O -o sa sa.rs 2>&1 | grep -E '^error' -A6 | head -20; ./sa
