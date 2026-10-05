cd /tmp/scratch/app; cat > build.rs <<'EOF'
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").map(|o| o == "windows").unwrap_or(false) {
        let d = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        println!("cargo:rustc-link-arg-bin=litepdf={d}/icon.o");
        println!("cargo:rerun-if-changed=icon.o");
    }
}
EOF
source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E "^error|Finished" -A8; pip install -q pefile 2>&1 | tail -1; python3 - <<'E'
import pefile
pe=pefile.PE('/tmp/scratch/app/target/x86_64-pc-windows-gnu/release/litepdf.exe')
for e in pe.DIRECTORY_ENTRY_RESOURCE.entries:
    print(e.name or pefile.RESOURCE_TYPE.get(e.struct.Id), [ (x.struct.Id, len(x.directory.entries)) for x in e.directory.entries])
E
