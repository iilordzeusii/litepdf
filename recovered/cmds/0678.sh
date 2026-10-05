cd /tmp/scratch/app/src; sed -i 's/let path = std::env::args().nth(1).unwrap_or_default();/let path = std::env::args().skip(1).find(|s| !s.starts_with("--")).unwrap_or_default();/' main.rs; grep -c 'starts_with("--")' main.rs
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head
