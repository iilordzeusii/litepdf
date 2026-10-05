tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
FocusForge comparison, read-only. Short version: I could NOT read FocusForge's viewer code, so the code-level comparison is unverified. Details:

VERIFIED (from GitHub iilordzeusii/focus-forge, private, via the connected account):
- package.json: Tauri 2 (@tauri-apps/api ^2.8), vite, typescript, chart.js, and pdfjs-dist ^5.4.149. So its PDF viewer is PDF.js (Mozilla), running in the Tauri WebView2 (Chromium). README says "editor/PDF/browser layouts".
- Caveat: that root package.json says version 1.0.0 while the zips go to v1.6.2, so the dependency list could be stale.
- Repo layout is only release zips at the root (1-focus-forge-v1.6.2.zip ... plus 4-index.html -> /src/main.ts). Source lives inside the zips; the GitHub tool returns them as mangled text, so I can't unpack src/main.ts (the file list shows src/main.ts, src/style.css, src-tauri/src/lib.rs). I have NOT seen how it sets scale, DPR, caching, tiling or workers.
  To finish this: send me (via you) the unzipped src/main.ts, or the zip as an attachment (under 20 MB), and I'll do the real diff.

ASSUMED (from how PDF.js works, https://mozilla.github.io/pdf.js/examples/index.html, not from his code):
- PDF.js parses and decodes in a Web Worker; the page is drawn to a <canvas> sized viewport x devicePixelRatio; the browser compositor then moves and zooms already-painted canvases on the GPU. So scrolling is just compositing bitmaps, with no per-frame work in JS. Zoom is typically CSS-stretch first, then re-render at the new scale.
- If FocusForge uses the stock PDFViewer, it also does lazy page rendering near the viewport, a page cache cap, and tile-free full-page canvases. If it is a custom loop it may differ.
- Rendering is canvas 2D in the webview; the pixels are real vectors re-rasterised by PDF.js, so very sharp at DPR.

Does it change the recommendation? Not the cause, but it shifts the options:
1. The cause of the lag in LitePDF is still what I found in the code: synchronous render + texture upload on the UI thread, no prefetch, and per-frame cloning. The FocusForge feel is explained by "bitmaps are rendered off the main path and the compositor scrolls them". Both of those fixes (render worker, prefetch, LRU texture cache, progressive low-res then sharp) copy that approach inside egui. Same result, no new engine. This stays my recommendation (Option A).
2. Option B: swap the front end to a webview (reuse FocusForge's PDF.js viewer, or my v1 with MuPDF-WASM). Pros: it is exactly the thing he calls smooth, so lowest risk of "still laggy". Cons: it abandons the native Rust egui app (bigger rewrite, Wry/WebView2 dependency, memory of a webview, annotation/OCR/redaction/signing integration re-done across a JS bridge), contradicts the "tiny footprint" brief, and the 339-page 2300x3124 book would use PDF.js canvases (memory heavy at 300 dpi, pdf.js caps canvas area).
3. My suggestion: do A first, measured with perf.log (max frame time during scroll and zoom). It is the smaller change and is where the real fix is. If, on his PC, it still doesn't feel like FocusForge, B is the fallback. That decision needs his word since it changes the product.

Nothing built. Waiting for his go (and optionally the unzipped FocusForge src/main.ts to turn the assumed section into verified).
EOF
