tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Re-ranked with touchpad + 144 Hz + "b3 felt better". Read-only, nothing built. I found one thing in my own code that is a likely b3-to-b4 regression (content arriving late), and one thing that explains why touchpad is eased in both builds.

1) TOUCHPAD PATH (VERIFIED in the winit/egui 0.34 source on disk): winit on Windows reports every WM_MOUSEWHEEL, including precision-touchpad scrolling, as LineDelta (fractions of a line, e.g. 0.1), never as pixel deltas. egui-winit turns that into unit=Line. egui only skips its easing for Point deltas under 8 or when the OS says "in touch"; Line is always eased. So his touchpad is a first-order low-pass filter: ~43 ms time constant (90% in 0.1 s) while fingers move, plus 100-200 ms of coasting after they lift. Our code adds no extra smoothing (app.rs just does `scroll -= smooth_scroll_delta`). This is identical in b3 and b4, so it explains "never snappy" but not "b4 worse than b3".

2) WHAT CHANGED b3 -> b4 (ranked by how well it fits "movement feels delayed, everything delayed"):
A. Content arrives late behind the motion (my best suspect, partly code-verified):
 - b3 drew a page on the UI thread: a freeze, but the page was sharp when it appeared. b4 never freezes, but a new page shows white (no base yet) or a soft 700 px base until the single render thread gets to it. With his scans each new page costs a full image decode.
 - His b4 log: renders up to 464-523 ms and the first at 704 ms, queue 6-8. (My sandbox did the same book in 10-40 ms, so his pages are much heavier than my test pages. I do not have his average render time; it is in the "render=Nx(avg A ms max M ms)" part of each log line.) One worker doing 0.3-0.5 s per job can only finish 2-3 pages per second, so a touchpad flick outruns it and pages whiz past white/soft. That reads as "everything is delayed".
 - Likely made worse by a bug in my worker (VERIFIED in render.rs): the per-page display-list cache keeps only 6 pages (`lists.len() > 6`), but the request list interleaves jobs for the visible pages plus pages up to 2.5 screens away (bases + tiles, priority classes 0-4). That is more than 6 pages while scrolling, so the cache thrashes and the page is re-interpreted (and its image re-decoded if MuPDF's store dropped it) for nearly every job. That can turn a ~100 ms page into ~500 ms per job. Not proven on his PC; the log would show it.
B. Dropped frames from GPU texture uploads (assumed): up to 12 MB (3 tiles) uploaded per frame, and the real OpenGL upload happens in paint, which perf.log does not time. At 144 Hz a frame has 6.9 ms; a 4 MB upload on shared-memory Intel graphics can exceed that, giving judder that feels like lag. His gap_max 7-13 ms means at least one missed refresh most seconds.
C. Sub-pixel handling (VERIFIED in code): in b4 tiles are snapped to whole physical pixels while the base picture is drawn at the unsnapped position, and b3 drew one image at the fractional position (smooth GPU filtering). Slow touchpad scrolling in b4 moves in 1 px steps, fine at 144 Hz but can look steppy/shimmery. Low-medium.
D. The 430-510 ms frame spikes: on scroll pauses my idle prefetch of text/links runs on the UI thread (line ~517). Real (my log hid it with the 400 ms filter) but he does not notice it, so lower priority.
E. Worker `request_repaint` per finished tile: adds extra frames but cannot add latency; not a storm (one per tile, not continuous). Ruled out as a cause, unless the log shows frames far above 144/s.
Ruled out by code: scroll is applied before painting in the same frame; clamping uses the same sizes (except for the first ~20 ms of opening a file); there is no frame queue of our own.

3) UPDATED b5-diag PLAN (still not built; waiting for his go)
Fixes I would make regardless: 
 - Render pool of 3 worker threads (his CPU has 12), each with its own document copy; display-list cache raised to 16 pages and jobs grouped by page so a page is interpreted once for its base and all its tiles.
 - Move text/link extraction to the workers.
 - Raw touchpad/wheel handling: read the wheel events ourselves and apply them immediately (no 43 ms low-pass; keep at most a ~30 ms ease for notched mice).
 - Base picture sharper (1400 px side, tiles still on top), and snap base and tiles the same way.
 - Cap uploads at 1 tile per frame in fast scroll.
Diagnostic toggles (Diagnostics menu, live, so he can feel A/B in a minute): wheel raw / eased; "b3 mode" = render a missing visible page synchronously on the UI thread like b3; pixel snapping on/off; upload budget 1 or 3 tiles; gl.finish at frame start; vsync on/off needs a launch flag (--vsync=off).
New log lines: per second, % of frames with any visible page white / base-only / fully sharp; worker jobs started/finished, queue wait and render ms split into list-build vs draw, and display-list cache hits/misses; frame gap histogram (p50/p95/p99, count above 1.5x refresh) with the 400 ms filter removed; per-stage timing for any frame over 30 ms; GL_RENDERER string, refresh rate, Windows GPU preference at start; wheel-to-applied-position time (time until 90% / 99% of a swipe is applied).

QUESTIONS for him (answers I can't get from code):
 1. While scrolling with the touchpad in b4, do pages flash white or look soft/blurry for a moment before they sharpen, or is the page always sharp and the motion itself lags behind your fingers? (This splits A from the touchpad easing.)
 2. Please paste the full b4 perf.log lines (or just the render=... and queue=... parts of 5-6 busy lines). The render average decides whether one render thread is the bottleneck.
 3. Is the delay worst when you flick fast through many pages, or also when you scroll slowly within one page?
EOF
