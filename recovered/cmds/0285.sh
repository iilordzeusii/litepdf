source ~/.cargo/env; mkdir -p /tmp/scratch/oc/src; cd /tmp/scratch/oc; cat > Cargo.toml <<'EOF'
[package]
name="oc"
version="0.1.0"
edition="2021"
[dependencies]
tesseract-rs = { version = "0.4.0", features = ["build-tesseract"] }
EOF
echo 'fn main(){}' > src/main.rs; timeout 60 cargo fetch 2>&1 | tail -2; D=$(ls -d ~/.cargo/registry/src/*/tesseract-rs-0.4.0); grep -n "^\[features\]" -A8 $D/Cargo.toml; grep -n "windows\|mingw\|cmake\|download\|curl\|http" $D/build.rs | head -30
