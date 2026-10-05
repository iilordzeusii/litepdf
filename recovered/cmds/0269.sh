cd /tmp/scratch/shot; cat > src/bin/q.rs <<'EOF'
use mupdf::{Document, TextPageFlags};
fn main(){ let d=Document::open("/tmp/scratch/t.pdf").unwrap(); let p=d.load_page(0).unwrap(); let tp=p.to_text_page(TextPageFlags::empty()).unwrap();
 for q in tp.search("SECRET-1234").unwrap(){ println!("quad {:?}",q); }
 for b in tp.blocks(){ for l in b.lines(){ for c in l.chars(){ if let Some(ch)=c.char(){ let q=c.quad(); if "SECRET-1234 belongs".contains(ch) { print!("{}[{:.0}-{:.0}] ",ch,q.ul.x,q.ur.x);} } } println!(); break; } break; } }
EOF
source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin q 2>&1 | grep -E "^error" -A9 | head); ./target/release/q | cut -c1-600
