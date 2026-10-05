cd /tmp/scratch/shot; cat > src/bin/aitest.rs <<'EOF'
#[path = "/tmp/scratch/app/src/extras.rs"]
mod extras;
#[path = "/tmp/scratch/app/src/ops.rs"]
#[allow(dead_code)]
mod ops;
fn main(){
    let s = extras::Settings{provider:"OpenRouter".into(), key:"sk-test".into(), model:"any/model".into()};
    // point at local mock
    let body = serde_json::json!({"model":"any/model","messages":[{"role":"user","content":"hi"}]});
    println!("{:?}", extras::ai_post("http://127.0.0.1:8765/v1", "Authorization: Bearer sk-test", &body, false));
    let g = extras::ai_post("http://127.0.0.1:8765/g", "x-goog-api-key: k", &body, true);
    println!("{:?}", g); let _=s;
}
EOF
cat > /tmp/mock.py <<'EOF'
from http.server import *
import json
class H(BaseHTTPRequestHandler):
    def do_POST(s):
        n=int(s.headers['Content-Length']); b=s.rfile.read(n)
        print("HDR",s.headers.get('Authorization'),s.headers.get('x-goog-api-key'),"BODY",b[:80],flush=True)
        r={"choices":[{"message":{"content":"hello from mock"}}]} if s.path=="/v1" else {"candidates":[{"content":{"parts":[{"text":"gem mock"}]}}]}
        o=json.dumps(r).encode(); s.send_response(200); s.send_header('Content-Length',str(len(o))); s.end_headers(); s.wfile.write(o)
HTTPServer(('127.0.0.1',8765),H).serve_forever()
EOF
python3 /tmp/mock.py > /tmp/mock.log 2>&1 &
sleep 1; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 100 cargo build --release --bin aitest 2>&1 | grep -E "^error" -A8 | head; ./target/release/aitest; cat /tmp/mock.log; pkill -f mock.py
