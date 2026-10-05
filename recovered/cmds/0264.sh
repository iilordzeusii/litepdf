cd ~/.cargo/registry/src/*/mupdf-0.8.0/src; grep -n "pub fn.*extract\|ExtractedImage" pdf/page.rs | head -5; grep -n "pub fn to_pixmap\|pub fn from_\|pub fn new_from" image.rs
