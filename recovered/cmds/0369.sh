cd /tmp/scratch; echo "18:30 new list from user (8 items). Investigating OCR 0 words: building e2e test via wine shim shot/target/release/ocr/tesseract" >> ~/NOTES_native.md
mkdir -p shot/target/release/ocr/tessdata; cp -n tess/td/eng.traineddata shot/target/release/ocr/tessdata/ 2>/dev/null
cat > shot/target/release/ocr/tesseract <<'EOF'
#!/bin/bash
# wine shim: convert unix paths in args to Z: paths
args=()
for a in "$@"; do case "$a" in /*) a="Z:${a//\//\\}";; esac; args+=("$a"); done
source /tmp/scratch/wenv2.sh; export DISPLAY=:77
exec $WINE /tmp/scratch/tess/bt/bin/tesseract.exe "${args[@]}"
EOF
chmod +x shot/target/release/ocr/tesseract
python3 - <<'EOF'
from PIL import Image, ImageDraw, ImageFont
import glob
txt="""All living organisms respire because they all need energy.
Respiration involves chemical reactions that occur in cells to break
down nutrients, such as glucose, to release energy. Oxygen is
usually needed for respiration to happen. This is the word equation
for respiration involving oxygen:
glucose + oxygen -> carbon dioxide + water (+ energy released)
Living things use this energy for movement, growth, repair and
reproduction."""
f=[x for x in glob.glob('/usr/share/fonts/**/*.ttf',recursive=True) if 'DejaVuSerif.ttf' in x or 'LiberationSerif-Regular' in x]
print(f[:1])
for dpi in (150,):
    W,H=int(8.27*dpi),int(11.69*dpi)
    im=Image.new('RGB',(W,H),'white'); d=ImageDraw.Draw(im)
    font=ImageFont.truetype(f[0],int(11*dpi/72)) if f else ImageFont.load_default()
    y=int(1.2*dpi)
    for l in txt.split('\n'):
        d.text((int(0.9*dpi),y),l,fill=(20,20,20),font=font); y+=int(0.28*dpi)
    im.save('/tmp/scratch/samp.jpg',quality=85,dpi=(dpi,dpi))
    im.save('/tmp/scratch/samp.pdf',resolution=dpi)
EOF
pdfimages -list samp.pdf | head -3; pdfinfo samp.pdf | grep "Page size"
cat > shot/src/bin/e2e.rs <<'EOF'
#[path = "/tmp/scratch/app/src/extras.rs"]
#[allow(dead_code)]
mod extras;
#[path = "/tmp/scratch/app/src/ops.rs"]
#[allow(dead_code)]
mod ops;
fn main(){
    let a: Vec<String> = std::env::args().collect();
    let mut d = mupdf::pdf::PdfDocument::open(&a[1]).unwrap();
    let t=std::time::Instant::now();
    let r = extras::ocr_document(&mut d, &mut |i,n| eprintln!("page {i}/{n}"));
    println!("{:?} {:?}", r, t.elapsed());
    ops::save(&d, &a[2], true).unwrap();
}
EOF
cd shot; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 80 cargo build --release --bin e2e 2>&1 | grep -E "^error" -A8 | head -20; ./target/release/e2e ../samp.pdf /tmp/samp_ocr.pdf; mutool draw -q -F text /tmp/samp_ocr.pdf | head -12
