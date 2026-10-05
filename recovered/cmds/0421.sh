cd /tmp/scratch/shot && git checkout Cargo.toml 2>/dev/null; sed -i '/^ort = /d' Cargo.toml; mkdir -p /tmp/scratch/ocrt/src/bin && cd /tmp/scratch/ocrt && mv /tmp/scratch/shot/src/bin/ocr2test.rs src/main.rs && rm -f /tmp/scratch/shot/Cargo.lock.bak
cat > Cargo.toml <<'EOF'
[package]
name="ocrt"
version="0.1.0"
edition="2021"
[dependencies]
mupdf = "0.8.0"
ort = { version = "=2.0.0-rc.10", default-features = false, features = ["std","load-dynamic","directml","ndarray"] }
[profile.release]
opt-level = 3
EOF
env -i HOME=$HOME PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.cargo/bin bash -c 'source ~/.cargo/env; cargo build --release 2>&1 | grep -E "^error|-->|Finished|^\s+\|" | head -60'
