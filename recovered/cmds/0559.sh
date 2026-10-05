cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; cp /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/{ocrcli,litepdf}.exe .; D="/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF"
run(){ rm -f "$D"/*.log; echo "##### $*"; env "$@" timeout 110 $WINE ocrcli.exe book.pdf book_o.pdf 2>&1 | grep -E "^words|OCR [0-9]"; grep -E "timing|created|CPU bench|WORKER|failed|adapters|build" "$D/ocr.log" | cut -c1-330; }
run LITEPDF_DET=1216
run LITEPDF_DET=960
run LITEPDF_FIXED=1 LITEPDF_DET=1216
