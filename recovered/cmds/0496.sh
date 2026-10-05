cd /tmp/scratch/app; grep -n "panic\|set_hook\|crash" Cargo.toml src/*.rs | head; grep -n "unwrap()" src/ocr.rs | head
