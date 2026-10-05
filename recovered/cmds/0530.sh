tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Analysis of the 7-10 s/page DirectML slowness (read-only, nothing changed). I cannot measure DirectML here (Wine has no GPU), so the causes below are ranked hypotheses from reading the code, plus one fact from my CPU run. The fix is to measure first.

What the logged "page N X.Xs" covers: everything the worker does for that page, i.e. MuPDF render at up to 200 dpi, CPU preprocessing of the detector canvas, detector run, box finding, per-line crop preprocessing, every recognizer run, CTC decode, and the JSON build. It does NOT include the text-layer write or the save (those happen in the parent after the P line). So ~8-10 s is all engine-side work, not save. Nothing is split per stage today, so I cannot say which part from his log.

Fact from my run: the same page work on CPU with 2 threads under Wine took 4.3-5 s per page (dense 1542-word page 20 s including start). His GPU at 7-10 s is slower than my 2-thread emulated CPU, so the GPU path is paying a per-call cost, not compute.

Ranked hypotheses:
1. Too many small DirectML calls. A normal page makes 1 detector run plus ~10-12 recognizer runs (batch 8, widths 320/640/960/1280; my test page with ~80 lines made 12 calls). If each DML Run carries ~0.6 s of fixed cost (kernel dispatch with memory-pattern off, GPU sync, readback of the full logits), that is 7-8 s. The old variable-shape build presumably used fewer, bigger calls.
2. The 960 and 1280 buckets are expensive (the recognizer is SVTR-style, cost grows with width, and each wide batch is 8 padded rows even if only 1-2 lines are real; my log shows batches like [1 line] and [2 lines] padded to 8 at 640).
3. Detector canvas 1152x1536 up to 2x upscale is ~2.4x the pixels of the old ~960 limit. Cheap on a GPU but the output map readback and the CPU flood fill over 1.77M pixels add up.
4. CPU-side preprocessing in plain Rust bilinear per pixel on one thread (detector canvas 1.77M px x3, then every crop). Likely 0.3-1 s a page, not the main cost but serial with the GPU.
5. Session options: memory_pattern off and sequential execution are the documented DML settings, so probably fine.

Proposal (order):
A. Add per-stage timing to ocr.log, one line per page: render ms, det preprocess ms, det run ms, box find ms, rec preprocess ms, rec run ms (sum plus number of calls and padded-row count), decode ms. Plus a one-line GPU-vs-CPU micro benchmark at engine start. Cheap, and tells us exactly where the 8 s goes. I would build this first so his next run gives a definitive answer.
B. Likely fix, to be confirmed by A: fewer, bigger recognizer calls: batch 16 or 32 for the 320/640 widths (most lines), 8 or 4 only for 960/1280; merge buckets to 3 (320, 800, 1280) so fewer shapes and fewer half-empty batches; drop the 1-line padded calls by folding stragglers into the next bucket up. Keep the shape count small (warm-up already compiles them once).
C. Detector canvas back to ~960x1280 (long side 1280) unless accuracy on small text drops; I would test accuracy on his three screenshots both ways.
D. Pipeline: render and preprocess page N+1 on a second thread while the GPU runs page N, and parallelize crop preprocessing across cores (std threads, no new dependencies).
E. Safety net: at start, time the first real page on GPU and, if per-page GPU time exceeds the CPU benchmark, switch to CPU automatically and log it. His CPU path should be fine: the old fallback exists.
Cost: A is about 20 minutes plus a test build; B, C, D another ~30-40 minutes with CPU-proxy tests only. All GPU speedups stay unverified until he runs them. Say go on A (plus B/C if you want them in the same build; I would ship A with B and C and let the timing lines confirm).
EOF
