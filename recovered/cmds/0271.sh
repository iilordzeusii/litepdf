cd /tmp/scratch/shot; cat > src/bin/q.rs <<'EOF'
use mupdf::pdf::PdfDocument; use mupdf::Image;
fn main(){ let d=PdfDocument::open("/tmp/scratch/t.pdf").unwrap(); let p=d.load_pdf_page(0).unwrap(); for i in p.images().unwrap(){ println!("{:?}",i); match d.extract_image(i.xref){Ok(e)=>{println!("ext {} bytes {:?}",e.encoded.len(),e.filter); match Image::from_bytes(&e.encoded){Ok(im)=>{match im.to_pixmap(){Ok(pm)=>println!("pm {}x{} n={} alpha={}",pm.width(),pm.height(),pm.n(),pm.alpha()),Err(x)=>println!("pm err {x}")}},Err(x)=>println!("img err {x}")}},Err(x)=>println!("ext err {x}")} } }
EOF
source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin q 2>&1 | grep -E "^error" -A9 | head); ./target/release/q | cut -c1-300
