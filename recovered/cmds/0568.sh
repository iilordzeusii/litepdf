cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
a="self.rows_map.get(&bucket).copied().unwrap_or(match bucket { 320 => 64, 800 => 32, _ => 16 })"
assert a in s
s=s.replace(a,"self.rows_map.get(&bucket).copied().unwrap_or_else(|| default_rows(bucket))")
s=s.replace("fn det_long()","""fn default_rows(bucket: usize) -> usize {
    let v: Vec<usize> = std::env::var("LITEPDF_ROWS").unwrap_or_default().split(',').filter_map(|x| x.trim().parse().ok()).collect();
    let i = match bucket { 320 => 0, 800 => 1, _ => 2 };
    if v.len() == 3 && v[i] >= 1 { return v[i]; }
    match bucket { 320 => 64, 800 => 32, _ => 16 }
}
fn det_long()""",1)
open('ocr.rs','w').write(s)
E
cd ..; source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu --bin ocrcli 2>&1 | grep -E "^error" -A8|head; cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; cp /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/ocrcli.exe .; D="/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF"
for r in "32,16,8" "64,32,8" "64,16,8"; do rm -f "$D"/*.log; echo "## rows $r"; LITEPDF_ROWS=$r LITEPDF_FIXED=1 timeout 50 $WINE ocrcli.exe p4.pdf p4_o.pdf 2>&1 | grep -E "^words"; grep -E "memory|timing" "$D/ocr.log" | cut -c1-260; done
