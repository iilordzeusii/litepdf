tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b7-Setup.part1 --message-stdin <<'EOF'
b7 installer part 1 of 2 (part 2 next). Join: copy /b LitePDF-b7-Setup.part1+LitePDF-b7-Setup.part2 LitePDF-Setup.exe. Full file 31,143,715 bytes. SHA-256 of joined file: a01e1a1276e4d62432297b336318670e7939a975f4e03bfd6a6cebcdc37dfca7 (joined hash verified here). litepdf.exe inside: 15,496,704 bytes, sha da29574a306415bca27568feb7520c97f0e7d2d3380f6a4325109cc33726b649. Title "build b7".
EOF
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b7-Setup.part2 --message-stdin <<'EOF'
b7 part 2 of 2 (joined SHA-256 a01e1a12...dfca7).

DIAGNOSIS (from code, not proven on his PC)
- egui only draws when an event arrives or something calls request_repaint. In b6 I removed the timers that kept repaints coming, so any moment where nothing requested a repaint (tile results waiting, input burst ending, pointer idle) could leave the window showing a stale frame until the next event. That fits "redraws every ~2 s / catches up". I cannot prove it was the cause: no GPU/real window here.
- "Fake inertia": a Windows precision touchpad itself sends a stream of decaying wheel events after the fingers lift (OS inertia). b5/b6 apply those raw and instantly, so the tail he feels is probably the OS's, not ours. We cannot tell OS inertia from real finger movement; the only way to cut it is to ignore small deltas after a swipe ends, which would be a guess. Not done, tell me if he wants it.
- b6 also turned vsync off, which I now think was a bad call, so reverted.

CHANGES
1. After every frame: if any input (pointer move, button, any event, scroll, zoom) happened in the last 500 ms, request another repaint immediately, so it redraws every display refresh during activity with a short idle tail, then sleeps. No timers involved. Input is applied in the frame it arrives (read from raw events at frame start).
2. Vsync back ON by default (--vsync=off to compare). glFinish stays off.
3. Still instant: raw scroll, raw zoom (pinch/ctrl+wheel), no notch ease, no zoom-settle timer, no edit debounce. UI animations unchanged.
4. Logging: per-second frames, frame avg/max, gap p50/p95/p99/max (unfiltered), new "GAP n ms between frames while active" lines whenever frames are more than 40 ms apart during activity, SLOW frame stage lines, wheel-swipe time-to-90%/99%, white/base/sharp counts.

VERIFIED HERE (Wine/headless proxy): builds, installer joins; 339 pages: scroll frame max 10.6 ms avg 0.6 ms, fast scroll max 9 ms, pinch zoom ok (max 8 ms), edit shows next frame, tabs ok.
ONLY ON HIS PC: whether the 2 s refresh is gone (this is the key test), vsync/present behaviour at 144 Hz, touchpad inertia feel, GPU upload cost. If it still hitches, his perf.log GAP and SLOW lines will say whether frames are not being drawn (GAP lines with small frame cost) or are slow to draw (SLOW lines). Repo not pushed.
EOF
