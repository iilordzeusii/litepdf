cd /tmp; tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b5-Setup.part1 --message-stdin <<'EOF'
b5 installer, part 1 of 2 (part 2 follows in the next message). Join: cat LitePDF-b5-Setup.part1 LitePDF-b5-Setup.part2 > LitePDF-Setup.exe (Windows: copy /b part1+part2 LitePDF-Setup.exe). Full file 31,155,285 bytes (b4 was 31,143,529, +11 KB). SHA-256 of the joined file: 5150e1fc96bb43526d9e3d5e42f5e604a83fb126f889347ca856e76db170c823 (I verified the joined hash here). litepdf.exe inside: 15,496,192 bytes, sha 2285a97eec7c24df26e284394eca3d2c78593f93a4ca1c1e14b541219cbcb436. Title bar says "build b5".
EOF
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b5-Setup.part2 --message-stdin <<'EOF'
b5 installer, part 2 of 2 (see part 1 for the join command and SHA-256 5150e1fc...c823).

WHAT CHANGED (all in, per the plan)
- 3 render workers sharing one queue. Each prefers pages already in its own display-list cache, which is now 16 pages (was 6) so same-page tile jobs stay together.
- Text/link extraction moved off the UI thread to the workers (that was the suspect for the 430-510 ms frame spikes). Clicks/selection still extract synchronously only if the cache is empty.
- Raw touchpad/wheel: no egui easing or coasting. Fractional touchpad deltas apply immediately, mouse notches get a ~30 ms ease. Zoom (ctrl) is untouched.
- Fast scroll uploads ~1 tile per frame (base images count half). Base and tiles now snap to whole pixels the same way. Base is 1100 px (was 700) so it is sharper while tiles load.
- Diagnostics menu with live toggles: raw wheel, render visible tiles on UI thread (b3 behaviour), pixel snapping, upload cap, glFinish. Launch with --vsync=off to test without vsync.
- perf.log: no 400 ms filter. Per second: gap p50/p95/p99/max, frame avg/max, uploads, worker renders, white/base-only/sharp frame counts, display-list cache hits/misses. Any frame over 30 ms gets a SLOW line with per-stage ms (poll/refresh/panels/thumbs/paint/requests). Worker jobs over 150 ms get a line (list build vs draw, cache hit/miss, worker id). Each wheel swipe logs time to first movement / 90% / 99% applied. Header logs GL renderer/vendor, vsync and the Windows per-app GPU preference. Memory: document is now held by UI + 3 workers, so RAM is higher on big books.

VERIFIED HERE (Wine/headless, proxy only, no GPU)
- Compiles clean; installer builds; joined hash matches.
- 339-page book: pool works; 30 bases in 423 ms total (first at 56 ms); replacing a queued list gets the wanted page in 127 ms; tile seams max channel diff 0 at 1.25x and 2 at 3x.
- Headless UI: slow scroll frame max 9.6 ms avg 0.7 ms; fast scroll max 21 ms; pinch zoom max 0.6 ms; edit shows next frame (180 ms sync tile, once); tabs open/switch/close ok; perf.log writes with the new fields, SLOW and worker lines.

ONLY ON HIS PC (not verifiable here)
- Whether it actually feels snappier, touchpad gain/speed (raw delta scale is my estimate: 40 pt per fractional line, 90 per notch, may need tuning), GPU texture upload cost, vsync/present behaviour, the GL renderer chosen, Text extraction results on his PDFs (hover/selection after the move), 144 Hz pacing.

ASK HIM: scroll the book for ~20 s, send perf.log. If still laggy, flip Diagnostics toggles one at a time (try raw wheel off, sync mode on, then relaunch with --vsync=off) and tell us which one changes it. Also: do pages flash white or soft while scrolling? Repo push still not done (not authorised).
EOF
