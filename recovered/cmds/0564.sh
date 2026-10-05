cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; cp /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/{ocrcli,litepdf}.exe .; D="/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF"; rm -f "$D"/*.log
LITEPDF_FIXED=1 timeout 100 $WINE ocrcli.exe p4.pdf p4_o.pdf 2>&1 | grep -E "^words"; grep -E "timing|created|batch|WORKER|failed" "$D/ocr.log" | cut -c1-300
