cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
a=s.index("        let r = std::panic::catch_unwind")
b=s.index("        *INIT_ERR.lock().unwrap() = e;")
s=s[:a]+"""        let e = if !dll.exists() { Some("file not found".to_string()) } else { ort::init_from(dll.to_string_lossy().to_string()).commit(); None };
"""+s[b:]
open('ocr.rs','w').write(s)
E
cd /tmp/scratch/ocrt; env -i HOME=$HOME PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.cargo/bin bash -c 'source ~/.cargo/env; cargo build --release 2>&1 | grep -E "^error|-->|Finished|^\s+\|" | head -40'
export LD=/tmp/scratch/ocrdl/lin/onnxruntime/capi/libonnxruntime.so.1.22.1; ./target/release/ocrt /tmp/scratch/cover.raw /tmp/scratch/ocrdl $LD 2>&1 | grep -v "^\x1b" | head; ./target/release/ocrt /tmp/scratch/samp.raw /tmp/scratch/ocrdl $LD 2>&1 | grep -v "^\x1b"|head -8
