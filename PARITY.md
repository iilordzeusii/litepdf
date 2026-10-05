# LitePDF rebuild: b13 parity checklist
Rebuilt from recorded commands (recovered/). Tick [x] ONLY when tested; say where (Wine = proxy, Windows = real PC).
[~] = checked only under Wine headless (proxy), not real PC. [ ] = untested.
Status: rebuilt exe is 15,509,504 bytes vs b13 15,517,184; installer 31,164,573 vs b13 31,153,930 (near-identical). Only headless Wine checks done so far (PROXY: no GPU/touchpad/real display). Real-PC testing: none yet.

- [~] Builds for Windows x64 (cross-compiled)  -> Wine-proxy: cross-built, links; runs headless
- [~] Open PDF, tabs (open several, close, switch; each tab own OCR child)  -> Wine-proxy uitest: open, switch (scroll+edit rev kept), close, re-open dedupes. Per-tab OCR child process untested
- [~] Tile renderer (display-list tiles, device-space scissor fix, zoomed vector-text fix, watchdog/JobFailed)  -> Wine-proxy uitest: stress zoom 1.62/8.0 no missing tiles after ~100ms, watchdog resends. Vector-text zoom fix: NOT visually tested
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
- [~] English OCR (PaddleOCR via ort, invisible text layer)  -> Wine-proxy ocrcli: cover.pdf 12 words, text layer verified via extraction (CPU path; DirectML GPU untested)
- [~] NSIS installer (+ models, onnxruntime/DirectML DLLs)  -> built; contents = b13 layout (exe, 3 DLLs, ocr models); install/uninstall on Windows NOT tested
- [ ] Crash handler
