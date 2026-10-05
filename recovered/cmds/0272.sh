cd /tmp/scratch/shot; cat > src/bin/q.rs <<'EOF'
use mupdf::pdf::PdfDocument;
fn main(){ let d=PdfDocument::open("/tmp/scratch/t.pdf").unwrap(); let o=d.new_indirect(3,0).unwrap(); let s=o.read_stream().unwrap(); println!("{} bytes head {:02x?} expect raw {}", s.len(), &s[..4], 2400*1800*3); }
EOF
source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin q 2>&1 | grep -E "^error" -A9 | head); ./target/release/q | cut -c1-300
