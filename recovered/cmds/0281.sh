source ~/.cargo/env; cd /tmp/scratch/sg; cat >> Cargo.toml <<'EOF'
lopdf = "0.39"
tokio = { version = "1", features = ["rt"] }
EOF
echo "11:19 signing scratch proof: /tmp/scratch/sg (underskrift 0.1.4 pure-Rust PAdES; signer.p12 pw=pw legacy). Building; then verify with pyhanko/openssl on host." >> ~/NOTES_native.md
(timeout 100 cargo build --release 2>&1 | grep -E "^error|Finished" -A8 | head -20 | cut -c1-180)
