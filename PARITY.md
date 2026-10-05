# LitePDF rebuild: b13 parity checklist
Rebuilt from recorded commands (recovered/). Tick [x] ONLY when tested; say where (Wine = proxy, Windows = real PC).
Status: nothing tested yet.

- [ ] Builds for Windows x64 (cross-compiled)
- [ ] Open PDF, tabs (open several, close, switch; each tab own OCR child)
- [ ] Tile renderer (display-list tiles, device-space scissor fix, zoomed vector-text fix, watchdog/JobFailed)
- [ ] Scroll: notch via Chromium-style animation, touchpad direct, momentum (tau 325 ms, 80 ms window), stop on other input
- [ ] Zoom: continuous, target zoom, cap 10 ln/s, +-0.4 ln/event; sys_lines
- [ ] AI page selector (3 buttons, range, images follow range)
- [ ] AI chat (Gemini/OpenRouter via curl, key local)
- [ ] Overlay (Diagnostics)
- [ ] Diagnostics menu: raw_wheel, sync_mode, snap, upload1
- [ ] Sliders: smoothing 1.0, distance, touchpad sens 0.7, pinch sens 1.0
- [ ] Input recorder -> input.log; perf.log
- [ ] Edit/annotate: highlight, underline, strike, ink, eraser(annotations), redaction marks, text
- [ ] Form filling
- [ ] Hyperlinks
- [ ] Merge / split / reorder / rotate / delete pages
- [ ] Compress
- [ ] Password / permissions
- [ ] Certificate signing
- [ ] Redaction (apply)
- [ ] English OCR (PaddleOCR via ort, invisible text layer)
- [ ] NSIS installer (+ models, onnxruntime/DirectML DLLs)
- [ ] Crash handler
