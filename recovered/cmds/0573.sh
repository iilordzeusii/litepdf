tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Read-only analysis for the b3 result (~8 s/page, no gain). Nothing built.

What this rules out: b2 pinned shapes only at run time, b3 pins them in the sessions (the ORT-documented fix), and both are ~8-10 s/page. His OLD build ran normal pages in 0.5-0.9 s on the same GPU with dynamic shapes. So "dynamic shapes are slow on DirectML" is NOT what is slowing him; shape pinning was a wrong lead as the main cause (it may still help a little). Whatever is wrong was introduced in the two fix builds and is common to both (or was always there and only the old path dodged it).

Things common to b2 and b3 that differ from the old build (all hypotheses, ranked):
1. Wrong GPU adapter in the worker. An RTX 3050 6 GB is usually a laptop part, which also has an integrated GPU. DirectML uses adapter index 0 by default (our code never sets device_id). If adapter 0 is the iGPU, OCR runs on the integrated GPU, and the old build may have hit the NVIDIA one by luck of the per-exe Windows graphics preference or enumeration order. I log the adapter NAMES (b3 ocr.log line "display adapters: ..."), but not which one DirectML actually picked. Evidence needed: that adapter line, and Task Manager > Performance while OCR runs (which GPU's "Compute"/"3D" is busy).
2. Unsupported ops falling back to CPU inside the DirectML session, with a GPU/CPU copy on each call. Same in old build though, so less likely unless old batches were bigger/fewer.
3. Per-run settings that the old build may not have had: memory_pattern=false and parallel=false (the DML doc says required; one ORT issue says no longer needed and removing them helped: https://github.com/microsoft/onnxruntime/issues/20983). I cannot check whether the old build set them, I have no copy of the old source.
4. Running in a child process (windowless, CREATE_NO_WINDOW). Unlikely to slow DML but it is new since old.
5. Recognizer padding/row counts: b3 pads to 64/32/8 rows, but compute for padded rows is small for a 3050; unlikely to explain 8 s.
6. CPU-side work: my Wine timing shows render ~0.1 s, det prep 0.04 s, rec prep 0.1-0.5 s, decode small, so CPU-side prep is not the 8 s.

What the b3 log will show (b3 prints per page): "page N timing: render, det prep, det run, boxes, rec prep, rec run (calls, rows used of rows run), decode, session creation". Read it like this:
- det run + rec run ~ the whole page time with few calls: the GPU calls themselves are slow (hypotheses 1-3).
- "session creation" non-zero on every page: sessions are being rebuilt (worker restarting); would show "worker restarts to release memory" lines.
- render/prep/decode big: CPU-side problem (unexpected).
- per-call time: rec run divided by calls. Compare with my CPU numbers: ~0.1-0.5 s per call on 2 CPU threads; if his GPU is near or worse than that per call, the GPU is not doing the work (iGPU, CPU fallback, or driver).
- Decisive free data: b3's watchdog fires after 6 GPU pages when pages 3-6 average over 2.5 s, and logs "CPU benchmark: X s for the same page". That tells us immediately if his CPU beats the GPU on the same page, and it may already have switched him to CPU if CPU was 20% faster. Please ask the user for that line, plus the "display adapters", "created ... session ... in N ms" lines, and 3 "page N timing" lines.
- Also useful: Task Manager while OCR runs: the litepdf.exe CPU %, and which GPU graph moves.

Proposed next build, only if the log points there: (a) enumerate DXGI adapters with index, vendor and dedicated memory, log which index DirectML uses, and pick the discrete NVIDIA/AMD adapter explicitly via device_id (ort supports DirectMLExecutionProvider with device id); (b) a quick micro-benchmark on each adapter (and CPU) before the first page, pick the fastest, log it; (c) re-test with memory_pattern/parallel off removed; (d) if DML stays slower than CPU, make CPU with all threads the default and keep GPU optional. I would not change anything else until the log confirms which of these it is.
EOF
