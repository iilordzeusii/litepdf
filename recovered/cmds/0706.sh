cd /tmp; python3 - <<'PYEOF'
s=open('/tmp/scratch/app/src/app.rs').read()
i=s.index("/// A wheel notch arrives")
open('/tmp/ez.rs','w').write(s[i:]+'''
fn main(){ let mut prev=0.0; for k in 0..=20 { let p=k as f32/20.0; let e=cubic_ease(p); assert!(e>=prev-1e-4); prev=e; if k%5==0 {println!("p={p:.2} e={e:.3}");} }
 assert!((cubic_ease(0.5)-0.5).abs()<0.01); assert!(is_notch(1.0)&&is_notch(-3.0)&&!is_notch(0.3)&&!is_notch(1.37)); println!("ok"); }
''')
PYEOF
rustc -O -o ez ez.rs 2>&1|head -3; ./ez
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app; timeout 100 cargo build --release --target x86_64-pc-windows-gnu --bin uitest 2>&1 | grep -E '^error' -A8 | head
