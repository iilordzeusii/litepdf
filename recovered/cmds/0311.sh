tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
OCR proof (second riskiest item) PASSED in scratch:
- Tesseract 5.5.2 + Leptonica 1.87.0 cross-compiled from Linux to a static Windows tesseract.exe (5.7 MB), using zig + cmake. It ran under Wine with the English "tessdata_best" model (15 MB) and read a 300-dpi page correctly: "Page one. Confidential account SECRET-1234 belongs to Alice. / Public sentence that must survive redaction."
- Text layer: I wrote the OCR words onto the ORIGINAL page as invisible text. Page size before and after is identical (595.44 x 841.92 pt, so the "pages get bigger after OCR" bug can't occur), the page image is untouched, pdftotext extracts the OCR text from the scan, and word boxes land within a few points of the true positions (checked against the original PDF's text positions). Small gap: words come out slightly merged in one line ("Pageone.") in pdftotext; I'm tuning that.
- Plan: ship tesseract.exe + eng.traineddata next to the app as a helper (installer size roughly 35-45 MB total, within his 100 MB OK). Tested on Linux/Wine only; Leptonica was built without PNG/JPEG so the app feeds it BMP.
Both risky items (signing, OCR) are now de-risked. Next: the real UI (toolbar/sidebar, annotation tools, ink, FreeText, eraser, find, forms), then AI + installer.
EOF
