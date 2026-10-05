tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b8-Setup.part1 --message-stdin <<'EOF'
b8 installer part 1 of 2 (part 2 next). Join: copy /b LitePDF-b8-Setup.part1+LitePDF-b8-Setup.part2 LitePDF-Setup.exe. Full file 31,153,638 bytes. SHA-256 of joined file: 147d22a365d625d5d598675dee93cdcfdb0fa19106d50fb1891c4b49150bb440 (joined hash verified here). litepdf.exe inside: 15,503,360 bytes, sha b9118108329292eaabed9887f9f3e5daf8a1a97bdb5186cfd2c4ea1878831da7. Title "build b8".
EOF
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b8-Setup.part2 --message-stdin <<'EOF'
b8 part 2 of 2 (joined SHA-256 147d22a3...b440).

AI PAGE SELECTOR (AI panel > Settings)
- 3 buttons: Current page / Page range / Full doc. Range has "from" and "to" fields (blank "to" = last page). No cap, no limits. Live line: "Sending N pages (pages a-b), text and N images".
- Checkboxes "Send page text" and "Send page images (one per page)" both follow the chosen pages. Images are one JPEG per page in the range (Gemini and OpenRouter request formats both carry multiple images), so a big range with images means a big payload; nothing blocks it.
- Bad input is handled: from>to swaps, out-of-range clamps to the document, non-numbers fall back to first/last page.

VIEWER (the Chromium-style items)
1. No rasterising on the UI thread: 3 workers render everything; the frame only draws finished textures. One exception kept on purpose: after you edit something, the stale visible tile is re-rendered on the UI thread once (about 100 ms on the 339-page test in Wine) so the edit shows immediately. The b3-style "render on UI thread" is only a Diagnostics toggle, off by default.
2. Fixed 1024 px tiles, visible first, then a margin ahead in the scroll direction; a new request list replaces stale jobs when you scroll fast (replace-list measured 127 ms to the wanted page in the pool test).
3. Always something on screen: instant scaled low-res base (now 1100 px) or the nearest-scale tiles while sharp ones render; white only if nothing exists yet. perf.log counts white/base/sharp frames.
4. Time-boxed uploads: texture uploads per frame stop after about 4 ms (new) and ~1 tile in fast scroll (b5).
5. Scroll/zoom is a pure scale of cached tiles; sharp tiles at the new scale are requested the same frame, no settle timer.
6. Annotations/selection/highlights are drawn over the same page rectangles with the same transform.
- Frame-time overlay: Diagnostics > "Show frame-time overlay" (frame ms, gap, fps, tiles, mem, queue; red when gap > 20 ms).
- Kept from b7: vsync on, repaint every refresh during activity, raw scroll/zoom, no easing, UI animations untouched, tabs unchanged.

VERIFIED HERE (Wine/headless proxy, no GPU): builds; installer joins; page-selection logic unit-tested (10 cases: current, range, swapped, blank to, clamp, garbage, empty doc, full); 339-page run: slow scroll frame max 8.8 ms avg 0.6 ms, fast scroll max 11.6 ms with only 2 blank frames (b7: 9-42), pinch zoom max 1.4 ms, edit visible next frame, tabs open/switch/close ok.
ONLY ON HIS PC: how it actually feels, GPU upload cost, vsync/144 Hz pacing, touchpad behaviour, overlay look, real AI requests (no key here, so the request building with multiple images is untested against Gemini/OpenRouter). Honest caveat: this is the same pipeline as b7 plus the upload time box and overlay; it will not be identical to Chromium. Please get his perf.log or an overlay screenshot. Repo not pushed.
EOF
