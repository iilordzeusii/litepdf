cd /tmp/scratch/shot; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 100 cargo build --release --bin shot 2>&1 | grep -E "^error|Finished" -A8|head; echo "18:55 save fix (unique snap, commit_file rename/reopen), merge/split menu removed, per-provider keys. need: windows build, settings switch test, package, report" >> ~/NOTES_native.md
cat > src/bin/settest.rs <<'EOF'
#[path = "/tmp/scratch/app/src/extras.rs"]
#[allow(dead_code)]
mod extras;
#[path = "/tmp/scratch/app/src/ops.rs"]
#[allow(dead_code)]
mod ops;
fn main(){
    std::env::set_var("APPDATA","/tmp/settest");
    let mut s = extras::Settings{provider:"Gemini".into(), key:"G1".into(), model:"gm".into(), ..Default::default()};
    s.switch_to("OpenRouter"); println!("after->OR key={:?} model={:?}", s.key, s.model);
    s.key="O1".into(); s.model="om".into(); extras::save_settings(&s);
    let mut r = extras::load_settings(); println!("reload prov={} key={} ", r.provider, r.key);
    r.switch_to("Gemini"); println!("->Gemini key={} model={}", r.key, r.model);
    r.switch_to("OpenRouter"); println!("->OR key={} model={}", r.key, r.model);
}
EOF
timeout 60 cargo build --release --bin settest 2>&1 | grep -E "^error" -A8; ./target/release/settest; (cd /tmp/scratch/app; source /tmp/scratch/wenv.sh; nohup cargo build --release --target x86_64-pc-windows-gnu > /tmp/scratch/winbuild4.log 2>&1 &); sleep 1
