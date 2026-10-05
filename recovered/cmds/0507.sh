cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1
python3 - <<'E'
from PIL import Image
for i,n in zip((3,4,5),("image-e02bd81e","image-216b4e7f","image-7dd452db")):
    im=Image.open(f"/downloads/{n}.png").convert("RGB"); print(i,im.size)
    s=2339/im.height; im=im.resize((int(im.width*s),2339),Image.LANCZOS)
    im.save(f"p{i}.pdf",resolution=200)
E
cp /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/{ocrcli,litepdf}.exe .
cat /tmp/scratch/wt/*.sh 2>/dev/null|head -3; ocrcli_help=$(ls); echo $ocrcli_help | head -c 400
grep -n "args\|a\[" /tmp/scratch/app/src/bin/ocrcli.rs | head
