tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Status (honest): still early, no UI image yet. Nothing in the GitHub repo changed yet.
EXISTS (scratch, not in repo): 
- A native Windows build toolchain on this Linux box that works (verified): Rust + MuPDF compiles to a Windows .exe. A small test exe opened a PDF and rendered page 1 under Wine ("pages=3 px=1191x1684").
- litepdf.exe skeleton, 10.8 MB (release build, links fine): opens a PDF, continuous scroll, pages rendered at physical-pixel size (zoom x screen DPI), pinch / Ctrl+wheel zoom. Built; NOT run in a window.
- NSIS installer build works (verified under Wine from earlier).
NOT verified: the window itself. Wine here has no OpenGL, so I can't open the egui window; real sharpness, pinch, speed and RAM need his PC. I'm making a CPU-rendered screenshot path to show UI layout (a software render of the same UI code, not a Windows capture); it hit a library version mismatch (needs egui 0.34, I'm upgrading the app from 0.31), then I'll rebuild and send the image.
NEXT, in order: 1) screenshot path + M0 image, 2) Adobe-style selection (char/word/line, double/triple click, copy) via MuPDF text layout, 3) annotations/FreeText box/live ink/eraser, 4) find, 5) merge/split/reorder/compress/passwords/redaction, 6) signing and OCR scratch proofs, then wire into the app, 7) AI (free-text model box), 8) installer, final exe + setup.exe with measured size/startup/RAM (Wine proxies). Riskiest still: signing and OCR text layer. Each full rebuild is slow on this 2-core box, so this will take a number of hours.
EOF
