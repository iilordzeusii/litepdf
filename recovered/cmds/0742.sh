tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
b10 status (not shipped yet, installer still to build):

Missing render, cause found and fixed. The tile renderer passed MuPDF a clip rect in page units, but MuPDF wants device pixels. Whenever he was zoomed in (scale above 1), vector text and graphics were culled. Full-page image pages were never fully culled, which matches his "full image loads fine" clue. It is not the hyperlinks. It has been there since the display-list tiles went in (b4). Reproduced headless in Wine on a generated vector PDF. Before the fix, scale 1.25 gave 62k wrong pixels. After, 0. Scale 3 now differs by a max of 18/255 on about 0.05% of pixels, a minor tile antialiasing difference that I haven't explained. I also added a watchdog that resends missing tiles after 400 ms, and per-job crash catching.

Zoom delay, cause: a Windows touchpad pinch arrives as ctrl+wheel with whole-number deltas. b9 treated that as a mouse notch and ran a 150 ms ease-in-out animation, which starts slowly. b10 copies Chromium's gesture_detector.ts: each ctrl-wheel event applies scale = clamp(exp(-dy/100), 0.75, 1.25) immediately, anchored at the cursor, with no animation. Still approximate: the +/- buttons keep their x1.25 jump rather than Chromium's preset steps.

Scroll: ported Chromium's ScrollOffsetAnimationCurve (cubic-bezier 0.42,0,0.58,1, retargeting with velocity preservation, 100 px per wheel tick). Two deliberate deviations: the first frame moves instead of easing from rest, and the duration is scaled to 0.5 of Chromium's. There are Diagnostics sliders for both length and distance. Unverified: whether Chromium treats a Windows precision touchpad as precise (direct) or wheel (animated).

Tested in Wine, which is a proxy only: the scroll, zoom, stress (0 missing tiles in 6 rounds), edit and tab tests pass with no regressions. Not verifiable here: real feel, GPU, vsync and touchpad. A Wine DirectWrite panic in worker threads also stopped one multi-thread comparison. I think that is Wine-only, but it isn't proven on real Windows.

Remaining: build the installer, split it into 2 parts, check the SHA-256, and send. I'll do that next.
EOF
