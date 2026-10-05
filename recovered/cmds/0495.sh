tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
OCR slowness: code review only, no build, nothing measured on his PC. All causes below are HYPOTHESES until we see his ocr.log.

What the code does today (facts): one engine per OCR run (not per page); engine start loads both models once; pages are rendered at 200 dpi on the document thread while the engine reads the previous page (2 pages queued); detector input is capped at 1536 px long side; recognizer runs line crops in batches of up to 12, padded to a multiple of 32 px wide. Every page therefore feeds the models many DIFFERENT input shapes (detector size per page, recognizer batch count x width varies per page). On CPU that is harmless. On DirectML, a new input shape can make the DML provider re-plan or recompile kernels, which is the best-known cause of "GPU slower than CPU" for small PP-OCR models (published ONNX Runtime DirectML guidance prefers fixed shapes; that is from memory of the docs, not re-checked now).

Ranked likely causes and fixes:
1. DirectML dynamic-shape recompiles (most likely if his log says DirectML). Fix: fixed shapes. Detector: resize/pad every page to one fixed canvas (e.g. 1024x1408 or two sizes for portrait/landscape). Recognizer: fixed batch of 8 or 16 (pad with blank rows) and only 4-5 fixed widths (e.g. 320, 640, 960, 1280, 1600). Then DML compiles each shape once and reuses it for all 400 pages.
2. GPU is not actually faster for these tiny models (hypothesis). Fix: a quick benchmark at start: time 2-3 pages on GPU and on CPU, then keep whichever is faster for the rest of the book, and say which in the status line and log.
3. CPU path using few threads, or intra-op threading scaling badly on small tensors (if the log says CPU). Fix: for CPU, run N worker sessions with 1-2 threads each, each on its own page, instead of one session with all threads. Typically 2-4x on multi-core CPUs.
4. Too many pixels: detector 1536 px and a 200 dpi render. Fix: detector long side 1024-1152 and render 150 dpi for pages with normal text. Detector cost drops roughly 2x. Small text risk: must re-check accuracy on the paragraph scan and the cover after the change.
5. Non-engine overhead on a 400-page book (smaller): snapshot save of the whole document before OCR, per-page font insertion in the text layer, and a full save plus reload at the end. Fix: measure first; likely seconds, not minutes.
6. Engine restart per OCR click (re-compiles DML graphs each time). Fix: keep the engine alive between runs.
Also worth saying to him: his "whole book in a minute" needs about 0.15 s/page. My CPU measurement here was about 1.0 s/page on 2 cores for a 200 dpi page; I cannot promise that figure on his GPU until shapes are fixed and measured on his machine.

Log lines to ask him for (%APPDATA%\LitePDF\ocr.log):
- "engine: DirectML (GPU) ..." means GPU started; "engine: CPU (N threads) GPU start failed, using CPU: <reason>" means CPU fallback and the reason (missing VC++ runtime / DirectML error text); "GPU run failed (...), switching to CPU" means GPU failed on page 1.
- Per page: "page N 4.2s DirectML (GPU): 310 words" is inference time per page. If the first pages are slow and later ones stay slow on DirectML, it points to cause 1; if they drop after a few pages, it is just warm-up; if CPU, N threads value shows cause 3.
- Last line "done: X words on Y pages in <time>" vs the sum of page times shows overhead outside the engine (cause 5).
Also useful: his CPU model and core count.
I will not build until you relay his go. Suggested go: items 1 + 2 + 3 together (fixed shapes, GPU-vs-CPU auto benchmark, parallel CPU sessions), plus per-page timing shown in the status line, then re-measure on his log.
EOF
