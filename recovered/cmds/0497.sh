tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Crash review (code reading only, nothing modified, nothing measured on his PC; all causes are HYPOTHESES). Paused, no builds.

Facts from the code: there is NO crash log and NO panic hook. The release profile uses panic="abort" and the exe is a windows-subsystem app, so any Rust panic kills the whole app instantly with no message and nothing written. A native crash inside DirectML/ONNX Runtime would also leave nothing.

Ranked hypotheses:
1. Post-OCR save + reload of a ~400-page book (my top suspect, since it happens at the END of the run). The old Tesseract build on his PC found no words, so this path (add a text layer to every page, compact-save the whole document, reload it) never ran for real on his machine. Here I only ran it on 1-page files. For 400 scan pages it makes a full snapshot, 400 added fonts/content streams, a compacting save and a reload: high RAM, long, and any MuPDF failure under panic=abort is a hard exit. Fix: write the result incrementally, or OCR in chunks, and avoid holding extra copies.
2. Native crash in DirectML / ONNX Runtime (access violation, GPU out of memory, device removed after a driver timeout while the GPU recompiles for every new input shape). Rust cannot catch this. DirectML.dll mismatch is less likely: the installer puts DirectML.dll 1.15.4 next to onnxruntime.dll in the install folder and Windows looks there first, but I have not verified which copy loads on his PC. Best fix: run OCR in a separate child process (litepdf.exe --ocr in out), so a crash kills only the OCR job, the app and his open document survive, and the UI says what happened.
3. A Rust panic (silent because of abort). Concrete spots: partial_cmp().unwrap() when sorting boxes and words (a NaN coordinate panics), indexing the recognizer output assuming a fixed shape, bilinear sampling on a zero-sized image. Less likely but cheap to harden.
4. Thread stack size: the OCR thread and engine worker are default Rust threads (2 MB stack). Model loading and DirectML graph setup on a small stack can overflow in native code. Fix: spawn with a 32-64 MB stack.
5. RAM pressure: up to about 4 full-size page renders in flight plus copies; fine at 200 dpi (about 11 MB each), only heavy for huge pages (cap is 4500 px long side, about 44 MB each).

Fixes to propose in the next build (after his go): panic hook writing %APPDATA%\LitePDF\crash.log with message, location, backtrace and the last OCR page; switch to panic="unwind" with catch_unwind around the OCR job; run OCR as a child process (covers native crashes); bigger thread stacks; incremental save; remove unwraps; log "saving result" and "reloading" stages.

What he can give us NOW without any build:
- ocr.log last lines: if the last line is "page N ..." with no "done:" line, it died during recognition at page N (then hypotheses 2-4); if there is a "done: X words ... in ..." line, it died while saving/reloading (hypothesis 1).
- Windows Event Viewer > Windows Logs > Application, newest "Application Error" for litepdf.exe: "Faulting module name" says DirectML.dll, onnxruntime.dll, litepdf.exe, or KERNELBASE, which tells native crash vs Rust abort. Also Reliability Monitor shows the same.
- Task Manager peak memory of litepdf.exe at the time (if he noticed), and how many pages were selected (whole book or a range).
EOF
