D=$(ls -d ~/.cargo/registry/src/*/mupdf-0.8.0); sed -n 20,110p $D/src/context.rs; grep -rn 'fz_locks_context\|locks' $D/src/*.rs | head
