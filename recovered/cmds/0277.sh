source ~/.cargo/env; mkdir -p /tmp/scratch/sg/src; cd /tmp/scratch/sg; cat > Cargo.toml <<'EOF'
[package]
name="sg"
version="0.1.0"
edition="2021"
[dependencies]
underskrift = { version = "0.1.4", default-features = false }
EOF
echo 'fn main(){}' > src/main.rs; timeout 60 cargo fetch 2>&1 | tail -1; D=$(ls -d ~/.cargo/registry/src/*/underskrift-0.1.4); sed -n 1,80p $D/README.md; grep -n "^\[features\]" -A25 $D/Cargo.toml | head -40; ls $D/examples 2>/dev/null; python3 -c "import pyhanko;print(pyhanko.__version__)"
