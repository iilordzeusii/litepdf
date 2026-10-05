source /tmp/scratch/wenv2.sh; export DISPLAY=:77; cd /tmp/scratch/wp; grep -c LitePDF user.reg; ls drive_c/users/*/Desktop drive_c/users/*/AppData/Roaming/Microsoft/Windows/Start\ Menu/Programs/LitePDF 2>&1 | head
cd /tmp/scratch/oc 2>/dev/null && ls | head -5
cd /tmp/scratch/wp/drive_c/LitePDFtest; ls /tmp/scratch/oc/*.bmp 2>/dev/null | head -1
B=$(ls /tmp/scratch/oc/*.bmp /tmp/scratch/tess/*.bmp 2>/dev/null | head -1); echo $B
cp "$B" /tmp/scratch/wp/drive_c/in.bmp; timeout 90 $WINE ocr/tesseract.exe 'C:\in.bmp' 'C:\out' --tessdata-dir 'C:\LitePDFtest\ocr\tessdata' -l eng 2>&1 | tail -2; head -c 200 /tmp/scratch/wp/drive_c/out.txt
timeout 60 $WINE uninstall.exe /S 2>&1|tail -1; sleep 3; ls /tmp/scratch/wp/drive_c/LitePDFtest 2>&1 | head
