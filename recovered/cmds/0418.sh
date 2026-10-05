cd /tmp/scratch/shot; cp -r /tmp/scratch/ocrdl/v2/det/mobile.onnx /tmp/scratch/ocrdl/det.onnx; cp /tmp/scratch/ocrdl/v2/rec/en_mobile/model.onnx /tmp/scratch/ocrdl/rec.onnx; cp /tmp/scratch/ocrdl/v2/rec/en_mobile/dict.txt /tmp/scratch/ocrdl/dict.txt
sed -i 's#^mupdf = "0.8.0"#mupdf = "0.8.0"\nort = { version = "=2.0.0-rc.10", default-features = false, features = ["std","load-dynamic","directml","ndarray"] }#' Cargo.toml
cat > src/bin/ocr2test.rs <<'EOF'
#[path = "/tmp/scratch/app/src/ocr.rs"]
mod ocr;
use mupdf::{Colorspace, Matrix, Document};
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let (pdf, pg, dpi, dir, dll) = (&a[1], a[2].parse::<i32>().unwrap(), a[3].parse::<f32>().unwrap(), &a[4], &a[5]);
    let d = Document::open(pdf).unwrap(); let p = d.load_page(pg).unwrap();
    let s = dpi / 72.0;
    let pm = p.to_pixmap(&Matrix::new_scale(s, s), &Colorspace::device_rgb(), false, true).unwrap();
    let t0 = std::time::Instant::now();
    let mut e = ocr::Engine::new(std::path::Path::new(dir), std::path::Path::new(dll), a.get(6).map(|x| x == "gpu").unwrap_or(false)).unwrap();
    println!("engine {} {} init {:?}", e.provider, e.note, t0.elapsed());
    for run in 0..2 {
        let t = std::time::Instant::now();
        let w = e.recognize(pm.samples(), pm.width() as usize, pm.height() as usize).unwrap();
        println!("run {run}: {} words in {:?}", w.len(), t.elapsed());
        if run == 1 { let line: Vec<String> = w.iter().map(|x| format!("{}@{:.0},{:.0},{:.0}x{:.0}", x.text, x.x, x.y, x.w, x.h)).collect(); println!("{}", line.join(" | ")); }
    }
}
EOF
python3 - <<'E'
from PIL import Image, ImageDraw, ImageFont
import glob
fs=glob.glob('/usr/share/fonts/**/*Bold*.ttf',recursive=True)+glob.glob('/usr/share/fonts/**/*.ttf',recursive=True)
print(fs[:3])
f1=ImageFont.truetype(fs[0],150); f2=ImageFont.truetype(fs[0],60)
im=Image.new('RGB',(1654,2339),(240,110,20)); d=ImageDraw.Draw(im)
d.text((120,500),"THE ORANGE",font=f1,fill=(255,230,200)); d.text((120,700),"COVER TITLE",font=f1,fill=(120,30,0))
d.text((120,1100),"A Novel by Jane Smith",font=f2,fill=(255,255,255))
d.text((120,2000),"Bestselling Edition 2026",font=f2,fill=(60,20,0))
im.save('/tmp/scratch/cover.pdf',resolution=200)
E
source /tmp/scratch/wenv.sh >/dev/null 2>&1; unset RUSTFLAGS CARGO_TARGET_DIR; cargo build --release --bin ocr2test 2>&1 | grep -E "^(error|warning: unused)|-->|Finished" | head -30
