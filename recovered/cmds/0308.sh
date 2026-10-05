cd /tmp/scratch/tess; python3 -c "
from PIL import Image
im=Image.open('sc-1.png').convert('L'); im.save('scan_raw.pdf',resolution=300.0); print(im.size)"; pdfinfo scan_raw.pdf | grep "Page size"; pdftotext scan_raw.pdf - | wc -c
convert sc-1.png sc.bmp 2>&1|head -1
W=/tmp/scratch/wineroot; export WINEPREFIX=/tmp/scratch/wp WINEARCH=win64 WINEDLLOVERRIDES="mscoree,mshtml=d" LD_LIBRARY_PATH=$W/usr/lib/x86_64-linux-gnu:$W/usr/lib/x86_64-linux-gnu/wine WINESERVER=$W/usr/lib/wine/wineserver64 WINEDLLPATH=$W/usr/lib/x86_64-linux-gnu/wine
(timeout 80 xvfb-run -a $W/usr/lib/wine/wine64 tesseract.exe 'Z:\tmp\scratch\tess\sc.bmp' 'Z:\tmp\scratch\tess\sc' --tessdata-dir 'Z:\tmp\scratch\tess\td' -l eng tsv 2>&1 | grep -v fixme | grep -v "pixRead\|pixaGen\|bmfCreate" | head -3); ls sc.tsv && awk -F'\t' '$1==5{print $7,$8,$9,$10,$12}' sc.tsv | head -5
cd ../shot; ./target/release/ocrtest ../tess/scan_raw.pdf ../tess/sc.tsv ../tess/scan_ocr.pdf 300; cd ../tess; pdftotext scan_ocr.pdf - | head -3; pdfinfo scan_ocr.pdf | grep "Page size"
