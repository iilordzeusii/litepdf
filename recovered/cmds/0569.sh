cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
def rep(a,b):
    global s
    assert a in s, a[:60]; s=s.replace(a,b,1)
rep("320 => 64, 800 => 32, _ => 16 }\n}","320 => 64, 800 => 32, _ => 8 }\n}")
rep("320 px x64, 800 px x32, 1280 px x16 lines","320 px x64, 800 px x32, 1280 px x8 lines")
rep("Err(e) if self.gpu && rows >= 8 =>","Err(e) if (self.gpu || std::env::var(\"LITEPDF_FORCEFAIL\").is_ok()) && rows >= 8 =>")
rep("        let t = Tensor::from_array(([rows, 3usize, 48, bucket], data)).map_err(|e| e.to_string())?;\n        let t0","        if rows >= 32 && std::env::var(\"LITEPDF_FORCEFAIL\").is_ok() { return Err(\"forced test failure\".into()); }\n        let t = Tensor::from_array(([rows, 3usize, 48, bucket], data)).map_err(|e| e.to_string())?;\n        let t0")
open('ocr.rs','w').write(s)
e=open('extras.rs').read()
e=e.replace("const RECYCLE_MB: u64 = 1200;","const RECYCLE_MB: u64 = 2200;",1)
open('extras.rs','w').write(e)
E
cd ..; source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E "^error" -A8|head -20; cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; cp /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/{ocrcli,litepdf}.exe .; D="/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF"; rm -f "$D"/*.log
LITEPDF_FORCEFAIL=1 LITEPDF_FIXED=1 timeout 60 $WINE ocrcli.exe p4.pdf p4_o.pdf 2>&1 | grep -E "^words"; grep -E "halving|timing|failed|WORKER|created" "$D/ocr.log" | cut -c1-230
