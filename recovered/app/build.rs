fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").map(|o| o == "windows").unwrap_or(false) {
        let d = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        println!("cargo:rustc-link-arg-bin=litepdf={d}/icon.o");
        println!("cargo:rerun-if-changed=icon.o");
    }
}
