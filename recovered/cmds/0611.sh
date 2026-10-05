cd /tmp; tools browser_guidance record --lease-id L-krn-j6vrusli5qcrbsippi4wbirosa --website github.com --flow 'Verify and download private repository ZIP' --outcome success --antibot-outcome not_observed --note 'config-a read lease already signed in; fetch(/owner/repo/raw/main/file) with default credentials follows redirect to raw.githubusercontent (credentials:include fails CORS); base64 via execute-js.' >/dev/null
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Done, read-only, and the user was right: I unzipped it. Got the real bytes of 1-focus-forge-v1.6.2.zip (38,773 bytes) through the signed-in browser session (the GitHub file tool mangles binaries), unzipped it in my sandbox, and read src/main.ts, style.css, package.json, tauri.conf.json, lib.rs. Repo untouched. Browser lease released.

VERIFIED from FocusForge v1.6.2 code (src/main.ts line 123, line 158, style.css .pdf-frame):
- It does NOT use PDF.js to display PDFs. pdfjs-dist is in package.json but `pdfjs` appears 0 times in main.ts, so it is an unused dependency (my earlier guess was wrong).
- The "PDF Viewer" is just `<iframe class="pdf-frame" src="blob:...#toolbar=1&navpanes=1&view=FitH">`. openPdf() does URL.createObjectURL(file) and sets the iframe src. No canvas code, no scale/DPR code, no worker, no tiling or cache code of its own: none of it exists in the app.
- So the smooth viewer is the PDF viewer built into WebView2 (Chromium's PDF viewer, which renders with PDFium). Everything he likes (zoom, scroll, sharpness) is that built-in viewer. Its internals I did not read; what follows about it is from general knowledge of Chromium and is assumed: PDFium renders in the browser/PDF plugin process, off the app's UI thread, tiles and caches pages, re-renders at devicePixelRatio, and the compositor scrolls ready bitmaps. Note it is a viewer only: no annotation editing, OCR, redaction, signing etc. (just Chromium's toolbar: zoom, rotate, print, basic search).
- Tauri side: lib.rs only disables WebView2 autofill and handles browser-tab events; nothing PDF-related.

DIFF vs current LitePDF (code-verified on my side, UI feel unmeasured):
- FocusForge: render work lives in Chromium's PDF plugin process, never blocks the app UI. LitePDF: MuPDF render, RGB->RGBA, and GPU texture upload happen on the egui UI thread inside the frame, no prefetch, small cache cleared at >10 pages, per-frame clones and hover scans.
- Both rasterise vectors at screen resolution (PDFium vs MuPDF), so sharpness is equal in principle; the difference is the pipeline (async tiled vs sync full page).

Does it change the recommendation? Partly:
1. The lesson from FocusForge is the same as before: render off the UI thread with prefetch and caching, keep per-frame work tiny. My plan A (worker thread, progressive low-res then sharp, byte-capped LRU, cheap hover/highlights, lazy sizes, perf.log) is still the fix and now has a concrete target: match the Chromium viewer's behaviour. Also add tiling for very high zoom on the 2300x3124 pages (render only the visible region at 100% scale), as Chromium does; I'd add that to plan A.
2. "Reuse FocusForge's approach" in the literal sense = embed WebView2's PDF viewer in an iframe. That would be smooth but gives up all LitePDF features (annotation/eraser, OCR, redact, sign, links logic, custom tabs) because the built-in viewer isn't scriptable. Not viable as the core. It could only be a read-only "fast view" mode, which I don't recommend.
3. A third option, MuPDF/PDFium-based native rendering with a separate process, is not needed; a render thread inside the app gets the same effect.
So: recommendation unchanged (plan A + tiling), with the corrected understanding that the benchmark is Chromium's PDFium viewer, not PDF.js. Still plan-only; waiting for his go.
EOF
