cat >> ~/NOTES_native.md <<'EOF'
11:35 UI PLAN (app.rs): left thumbnails; top toolbar (Open/Save/tools: Select, Highlight, Underline, Strike, Ink, Text(FreeText on-page TextEdit), Eraser(delete ink annots near pointer), Redact(rect->redact annot, apply), Find(Ctrl+F)), menus for Merge/Split/Reorder/Compress/Protect/Sign/OCR/AI (call ops.rs), model name = free text box + remember last. Annots applied live into PdfDocument (page.add_*), invalidate tex cache; live ink drawn as egui overlay polyline during drag. Forms via widgets (set_value). rfd for file dialogs. Tests via shot sim events.
EOF
cd ~/.cargo/registry/src/*/mupdf-0.8.0/src/pdf; grep -n "pub fn" widget.rs | head -40; grep -n "pub fn save\b" -A12 document.rs | head -20; ls ~/.cargo/registry/src/*/ | grep -i "^rfd"
