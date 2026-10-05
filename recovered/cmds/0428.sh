cd /tmp/scratch/ocrt; python3 - <<'E'
s=open('src/main.rs').read()
s=s.replace('    println!("engine','    let t0 = std::time::Instant::now();\n    let mut e = ocr::Engine::new(std::path::Path::new(dir), std::path::Path::new(dll), a.get(4).map(|x| x == "gpu").unwrap_or(false)).unwrap();\n    println!("engine',1)
open('src/main.rs','w').write(s)
from PIL import Image
import struct
def raw(png,out):
    im=Image.open(png).convert('RGB'); open(out,'wb').write(struct.pack('<II',*im.size)+im.tobytes())
raw('/tmp/scratch/samp.jpg','/tmp/scratch/samp.raw')
E
python3 - <<'E'
from PIL import Image, ImageDraw, ImageFont
import struct,glob
f=[x for x in glob.glob('/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf')][0]
f1=ImageFont.truetype(f,150); f2=ImageFont.truetype(f,60)
im=Image.new('RGB',(1654,2339),(240,110,20)); d=ImageDraw.Draw(im)
d.text((120,500),"THE ORANGE",font=f1,fill=(255,230,200)); d.text((120,700),"COVER TITLE",font=f1,fill=(120,30,0))
d.text((120,1100),"A Novel by Jane Smith",font=f2,fill=(255,255,255)); d.text((120,2000),"Bestselling Edition 2026",font=f2,fill=(60,20,0))
im.save('/tmp/scratch/cover.png'); open('/tmp/scratch/cover.raw','wb').write(struct.pack('<II',*im.size)+im.tobytes())
E
env -i HOME=$HOME PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.cargo/bin bash -c 'source ~/.cargo/env; cargo build --release 2>&1 | grep -E "^error|-->|Finished|^\s+\|" | head -60'
