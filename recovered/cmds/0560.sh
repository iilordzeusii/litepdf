cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; D="/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF"
cat > /tmp/runall.sh <<'EOF'
cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; D="/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF"
for cfg in "LITEPDF_DET=1216" "LITEPDF_DET=960" "LITEPDF_FIXED=1 LITEPDF_DET=1216"; do
 rm -f "$D"/*.log; echo "##### $cfg"; env $cfg timeout 200 $WINE ocrcli.exe book.pdf book_o_$$.pdf 2>&1 | grep -E "^words|OCR [0-9]"; grep -E "timing|created|CPU bench|WORKER|failed|adapters|build" "$D/ocr.log" | cut -c1-330
done; echo ALLDONE
EOF
nohup bash /tmp/runall.sh > /tmp/runall.out 2>&1 &
sleep 100; cat /tmp/runall.out
