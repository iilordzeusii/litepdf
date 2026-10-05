tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Progress (build still in progress, not final): PaddleOCR is in and Tesseract is removed.
DONE and tested here (Wine/Linux = proxy for Windows):
- PP-OCR mobile detector (4.6 MB) + English recognizer (7.5 MB) on ONNX Runtime 1.22 (Windows DirectML build), written in Rust. GPU (DirectML) is tried first; if it fails to start or fails on the first page it switches to CPU with the same models. The engine used is shown in the status line and logged to ocr.log.
- Accuracy checks (CPU): synthetic orange cover with big cream and dark-red titles at 200 dpi, all 12 words read correctly (THE ORANGE / COVER TITLE / A Novel by Jane Smith / Bestselling Edition 2026), 1.0 s on 2 cores. His pasted paragraph scan: 66 words, correct, 1.3 s/page. Under Wine: Windows onnxruntime.dll loads, DirectML correctly fails (no GPU there) and the CPU fallback runs and writes the text layer (13 words on the cover, 66 on the paragraph).
- Skip pages that already have text works (re-run on an OCRed file: skipped=1, nothing done); "Re-OCR pages that already have text" checkbox forces it. Pipeline renders the next pages at 200 dpi while the engine reads the current one.
- Page box (type number + Enter, shows "Page N / total" in toolbar), filename + unsaved star in the window title and toolbar: coded and compiled, not yet visually checked (Wine has no GL).
UNVERIFIED (only his PC can confirm): DirectML GPU path and its speed on the RTX 3050; the real DLL load on his machine (needs the Microsoft Visual C++ runtime, which almost every Windows PC has; if missing, the app shows a clear error instead of crashing).
HEADS UP on delivery: the installer is now 31 MB (ORT 16 MB + DirectML 18 MB + models 12 MB + exe 15 MB, LZMA), over the 20 MiB attachment cap. I can't attach it as one file. Options: you upload it to a link he can open, or I split it into two parts he rejoins. Tell me which; I will finish the rest first.
STILL TO DO: compression rework (JPEG/ICC, DPI choice, before/after), zoom lag fix, tabs. Continuing now.
EOF
