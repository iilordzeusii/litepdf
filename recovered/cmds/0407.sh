cat >> ~/NOTES_native.md <<'EOF'
19:03 GO from user (Slack 1791120732.340619) for plan: skip OCR'd pages (+force), page box, filename title/toolbar, compress fix (JPEG/ICC, DPI, before/after), OCR speed (parallel pages, lower dpi), extra-pass OCR for covers (min-channel, luma stretch, inverted, psm 11), zoom lag bg render, tabs. Also research alt OCR engine (PaddleOCR ONNX/DirectML, Windows OCR) -> short recommendation; keep Tesseract default. One installer at end. Repo push still held.
EOF
cd ~/.cargo/registry/src/*/mupdf-0.8.0/src; grep -rn "load_image\|pub fn read_raw_stream\|pub fn read_stream\|pub fn read_stream_raw\|fn from_pdf\|pub fn to_pixmap" --include=*.rs . | head -12; grep -n "pub struct PageImageInfo" -A16 pdf/page.rs; grep -n "fn replace_image" -A12 pdf/page.rs | head -30
