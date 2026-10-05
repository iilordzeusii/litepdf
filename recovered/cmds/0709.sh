tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b9-Setup.part1 --message-stdin <<'EOF'
b9 installer part 1 of 2 (part 2 next). Join: copy /b LitePDF-b9-Setup.part1+LitePDF-b9-Setup.part2 LitePDF-Setup.exe. Full file 31,156,125 bytes. SHA-256 of joined file: 5e8aa2bd880c12c5c91d787fcff82c5734545f22bc5104805b4a67626f984172 (joined hash verified here). litepdf.exe inside: 15,504,896 bytes, sha 04d5ac7360b1f36113e44eeff3a867d6e0b2df47c12dfb883b91f91b9296de25. Title "build b9".
EOF
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b9-Setup.part2 --message-stdin <<'EOF'
b9 part 2 of 2 (joined SHA-256 5e8aa2bd...4172).

WHY b8 FELT "TOO FAST, NOT SMOOTH, ROBOTIC" (from my code)
- Any wheel/touchpad event with |delta| >= 0.5 line was treated as a mouse notch and jumped 90 pt instantly, so fast touchpad swipes (which send bigger fractional deltas) were multiplied and jumpy. Mouse notches also jumped with no motion. Ctrl+wheel and pinch zoom applied each step as an instant jump (x1.22 per notch).

CHROMIUM FACTS (verified from source I fetched today)
- One wheel tick (WHEEL_DELTA) = 3 lines x 100/3 = 100 px: https://chromium.googlesource.com/chromium/src/+/HEAD/ui/events/blink/web_input_event_builders_win.cc (kScrollbarPixelsPerLine = 100/3; comment: "100 px per three lines ... Even though we have smooth scrolling, we don't make this as large as IE").
- Smooth scroll animation uses an ease-in-out cubic bezier (0.42, 0, 0.58, 1); constant duration is 9/60 s = 150 ms; other modes (delta-based, inverse-delta 100-200 ms) exist: https://chromium.googlesource.com/chromium/src/+/HEAD/cc/animation/scroll_offset_animation_curve.cc
- NOT verified: which duration mode wheel scrolling actually uses in the PDF viewer, Chromium's exact zoom step size/animation for ctrl+wheel in the PDF viewer, and that precision-touchpad deltas are applied unanimated (general knowledge). I did not find those in the files I read, so the zoom part is my approximation, not a copy.

CHANGES
1. Mouse notches (whole-number line deltas only) now scroll 100 pt per notch (was 90 instant) animated with Chromium's curve over 150 ms. Another notch mid-animation retargets: the remaining distance plus the new one restarts the 150 ms curve (no stacking jumps).
2. Touchpad (fractional deltas) is no longer mistaken for notches: applied directly, instantly, at the same 40 pt per line as before, so it follows your fingers with no easing and no added delay. Any inertia is the OS's.
3. Ctrl+notch zoom: same x1.22 per notch but animated over 150 ms with the same curve, anchored under the cursor. Touchpad pinch / fractional ctrl+wheel stays direct.
Note: ease-in-out by design starts slow, so a mouse-notch scroll begins gently (about 13% of the distance after the first quarter of the 150 ms). If he finds that laggy, it is the one knob (duration or curve) to change.
Unchanged: tabs, page selector, overlay, vsync, tiling pipeline, UI animations. The +/- zoom buttons still jump (not changed).

VERIFIED HERE: builds; installer joins; ease function unit-tested (monotonic, 0 to 1, midpoint exactly 0.5, 25% gives 0.129, 75% gives 0.871); notch-vs-touchpad classifier tested (1.0, -3.0 notches; 0.3, 1.37 not); headless 339-page run still fine (scroll frame max 4.5 ms avg 0.5, fast scroll 11 ms, pinch zoom 5 ms, edit/tabs ok).
ONLY ON HIS PC: how it feels (speed per notch, the touchpad gain, the animation start), real wheel event types from his touchpad (if his touchpad sends whole-number deltas it will take the animated path), zoom feel. Repo not pushed. Please ask him: mouse or touchpad, and whether speed is now right.
EOF
