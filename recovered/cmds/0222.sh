source ~/.cargo/env; mkdir -p /tmp/scratch/shot/src; cd /tmp/scratch/shot; cat > Cargo.toml <<'EOF'
[package]
name="shot"
version="0.1.0"
edition="2021"
[dependencies]
egui_software_backend = "0.0.3"
egui = "0.31"
mupdf = "0.8.0"
EOF
echo 'fn main(){}' > src/main.rs; timeout 90 cargo fetch 2>&1 | tail -2; ls ~/.cargo/registry/src/*/egui_software_backend-0.0.3/; grep -n "pub fn\|pub struct" ~/.cargo/registry/src/*/egui_software_backend-0.0.3/src/lib.rs | head -20; grep -n "egui" ~/.cargo/registry/src/*/egui_software_backend-0.0.3/Cargo.toml | head
