cd ~/.cargo/registry/src/*/mupdf-0.8.0/src; grep -n "pub fn" pixmap.rs | head -40; grep -n "pub fn.*image" pdf/page.rs | head; grep -n "pub enum ImageFormat" -A8 pixmap.rs
