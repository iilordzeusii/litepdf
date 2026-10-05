tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Read-only analysis. Note: I can't see his Slack log myself (not in my observation store), so I rely on your reading: new-engine runs stop after page 4's line, same place whether the run starts at page 1 or 3.
What the code tells us about ordering (fact): the "page N ...: W words" line is written when page N's result is applied, BEFORE its text layer is added. The worker is already recognizing page N+1 (or N+2) at the same time. So "last line = page 4" means the process died either (a) inside add_text_layer for page 4, or (b) inside the engine on page 5/6 (detector or recognizer). The same death point from different start pages says the cause is the CONTENT/shape of page 5-6, not run length or memory growth.
Candidates for a page-specific kill, ranked (all hypotheses):
1. Native DirectML failure on a large or new input shape (most likely). Per his timings the dense page 3 already costs 5.3 s warm and 66 s cold; a single DML dispatch or compile that runs more than about 2 s can trigger Windows' GPU timeout (TDR, "device removed"); ONNX Runtime's DirectML provider can then terminate the process instead of returning an error. Page 5 probably produces a recognizer batch shape that is new and large (up to 12 lines x up to 4000 px wide, because very wide lines are only clamped at 4000 px) or a very dense detector map. Fix: small fixed shapes (batch 4-8, widths capped about 960-1280 with long lines split into chunks, one fixed detector canvas), and automatic fallback to CPU for the rest of the book after any engine error.
2. add_text_layer for page 4 (smaller chance): page 3 with 1363 words worked, so size alone is not it; but odd characters or very long text strings in the content stream, or MuPDF failing while inserting the font/contents, would be a hard exit under panic=abort.
3. Rust panic in ocr.rs (abort, silent): partial_cmp().unwrap() when sorting, indexing the recognizer output, zero-size crop. Possible but the same page every time points more to shape/content than to a rare NaN.
4. Small thread stack (2 MB) for native graph setup: less likely since pages 1-4 ran fine.
What the next build must write (all to %APPDATA%\LitePDF, each flushed immediately):
- crash.log from a panic hook: message, source location, backtrace, plus the current stage and page.
- crash.log from a Windows unhandled-exception filter: exception code (e.g. 0xC0000005 access violation, 0x887A0005 device removed), faulting module (DirectML.dll / onnxruntime.dll / litepdf.exe) and address; optionally a minidump.
- ocr.log stage markers BEFORE each step: "page N start", "page N detect HxW -> K boxes", "page N recognize batch i/m shape [n,3,48,w]", "page N text layer", "saving", "reload", so the last line shows exactly where it died; plus engine name and timing per page.
- OCR in a child process, so the parent logs the child's exit code and the last stage and tells him which page failed, and the app and open file survive.
- Optional: ONNX Runtime's own log written to ocr_ort.log.
I have changed nothing and will wait for your go.
EOF
