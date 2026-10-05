tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b6-Setup.part1 --message-stdin <<'EOF'
b6 installer part 1 of 2 (part 2 next). Join: copy /b LitePDF-b6-Setup.part1+LitePDF-b6-Setup.part2 LitePDF-Setup.exe (Linux: cat). Full file 31,157,298 bytes. SHA-256 of joined file: 4b23709343aff6ecc738375f594da61ae5244150d9f67e4487477bb7ccc3dc35 (joined hash verified here). litepdf.exe inside: 15,495,680 bytes, sha a5a39e2f445deb533e4e80b9614f093b86607684b3901b2ad01a2649eb417e23. Title "build b6".
EOF
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b6-Setup.part2 --message-stdin <<'EOF'
b6 part 2 of 2 (SHA-256 of joined file 4b237093...dc35).

UI look unchanged (menus/tabs/hover animations kept; I reverted my animation-off experiment). No b5 perf.log or feedback exists, only his "delay is really bad".

REMOVED / CHANGED (movement + zoom latency only)
1. Mouse-notch 30 ms ease: gone, notch applies instantly.
2. Touchpad/wheel scroll: raw only (egui's ~43 ms eased smoothing and coasting bypassed; was already so in b5). The raw/eased toggle is removed from Diagnostics.
3. Zoom: found a real one. egui smooths ctrl+wheel zoom, and a Windows touchpad pinch typically arrives as ctrl+wheel, so b5 zoom was eased. Now zoom is computed from raw events (pinch gesture, multi-touch, ctrl+wheel) with the same 1/200 per point rate, applied the same frame. Cursor anchor kept.
4. Zoom settle timer (140 ms before sharp tiles for the new scale were requested, plus 150 ms repaint timer): gone. Tiles for the new scale are requested every frame, visible ones first.
5. Edit refresh debounce (250 ms idle + 120 ms retry timers): gone, refresh is immediate. Edited tiles that are stale render synchronously so the edit shows on the next frame.
6. Vsync now OFF by default (lowest latency, can tear). --vsync=on to compare. glFinish stays off by default.
7. Fix: command-line flags like --vsync no longer get mistaken for the file path.
Not changed: text extraction is already off the UI thread, uploads capped at ~1 tile per frame in fast scroll (that is a smoothness guard, a toggle in Diagnostics; if he still sees lag, turn it off).

VERIFIED HERE (Wine/headless proxy, no GPU/real input)
Builds; installer joins correctly; 339-page book: slow scroll frame max 12 ms avg 0.9 ms, fast scroll max 13 ms, pinch zoom 1.0 to 2.4 works (frame max ~5-10 ms), after-zoom sharp tiles arrive, edit shows next frame (113 ms one-time sync tile), tabs ok.
ONLY ON HIS PC
Whether the delay is gone, touchpad pinch actually arriving as ctrl+wheel/Zoom events and its gain, vsync-off feel/tearing at 144 Hz, GPU upload cost, the GL renderer picked. Not proven: that these removed delays are the whole cause of the "delay" he feels; present path and driver behaviour can't be tested here. Please get his perf.log (SLOW lines and wheel swipe lines now show where time goes). Repo not pushed.
EOF
