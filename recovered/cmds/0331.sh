cd ~/.cargo/registry/src/*/mupdf-0.8.0/src; grep -rn "struct Permission" -A14 pdf/document.rs | head -24; grep -n "needs_password\|pub fn open" pdf/document.rs | head
