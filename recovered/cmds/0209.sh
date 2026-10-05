source ~/.cargo/env; mkdir -p /tmp/scratch/app/src && cd /tmp/scratch/app && cat > Cargo.toml <<'EOF'
[package]
name = "litepdf"
version = "0.1.0"
edition = "2021"
[dependencies]
eframe = { version = "0.31", default-features = false, features = ["glow","default_fonts"] }
mupdf = "0.8.0"
[profile.release]
opt-level = 3
lto = true
codegen-units = 1
strip = true
panic = "abort"
EOF
echo 'fn main(){}' > src/main.rs; (timeout 100 cargo fetch 2>&1 | tail -3); ls /usr/lib/x86_64-linux-gnu | grep -c -i "libGL\|llvmpipe\|swrast"
