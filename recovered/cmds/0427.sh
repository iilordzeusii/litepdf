cd /tmp/scratch/ocrt; sed -i '/^mupdf/d' Cargo.toml
python3 - <<'E'
import re
s=open('src/main.rs').read()
s=s.replace("use mupdf::{Colorspace, Matrix, Document};\n","")
s=re.sub(r"let \(pdf, pg, dpi, dir, dll\).*?\n.*?\n.*?\n.*?\n.*?unwrap\(\);\n","""let (img, dir, dll) = (&a[1], &a[2], &a[3]);
    let raw = std::fs::read(img).unwrap(); let pw = u32::from_le_bytes(raw[0..4].try_into().unwrap()) as usize; let ph = u32::from_le_bytes(raw[4..8].try_into().unwrap()) as usize; let pix = &raw[8..];
""",s,flags=re.S)
s=s.replace("pm.samples()","pix").replace("pm.width() as usize","pw").replace("pm.height() as usize","ph").replace("a.get(6)","a.get(4)")
open('src/main.rs','w').write(s)
E
sed -n 1,12p src/main.rs
python3 - <<'E'
from PIL import Image
import struct
for n,src in [("cover","/tmp/scratch/cover.pdf")]: pass
im=Image.open('/tmp/scratch/cover.pdf') if False else None
E
ls /tmp/scratch/*.png /tmp/scratch/samp* 2>/dev/null | head
