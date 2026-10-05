cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; rm -f "$APPDATA"/LitePDF/ocr.log "$APPDATA"/LitePDF/crash.log
python3 - <<'E'
from PIL import Image
ims=[Image.open(f"p{i}.pdf") if False else None for i in (3,4,5)]
E
python3 -c "
from PIL import Image
import glob
n=['image-e02bd81e','image-216b4e7f','image-7dd452db']
L=[]
for x in n:
    im=Image.open(f'/downloads/{x}.png').convert('RGB'); s=2339/im.height; L.append(im.resize((int(im.width*s),2339),Image.LANCZOS))
L[0].save('book.pdf',save_all=True,append_images=L[1:],resolution=200)"
( time timeout 110 $WINE ocrcli.exe book.pdf book_o.pdf ) 2>&1 | grep -v "^[0-9a-f]*:fixme\|err:" | tail -20
echo ---LOG; tail -40 "$APPDATA"/LitePDF/ocr.log; ls "$APPDATA"/LitePDF
