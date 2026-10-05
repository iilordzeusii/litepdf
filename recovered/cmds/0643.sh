tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-Setup-b4.part2 --message-stdin <<'EOF'
b4 installer, part 2 of 2 (15,143,529 bytes). Joined file SHA-256 07b6bf80e9d2db7c49b55e163cc33b18cf2412be11880e05254f5c450d347eef (I re-joined the parts here and the hash matches). litepdf.exe inside: 15,464,960 bytes, SHA-256 a7254e7a3d5c4ce7746194d4b5fd925993eda7cbede4f18013aecab1e1855a6e. Title bar says "build b4".

WHAT CHANGED (all in one build; repo NOT pushed)
Viewer (the lag fix):
- Pages are now drawn by a background render thread with its own copy of the document. The UI thread only uploads finished pictures. The UI never waits on MuPDF while scrolling or zooming.
- Tiling: each page is cut into 1024x1024 px tiles at the exact screen resolution (zoom x display scale, snapped to whole pixels, so 1 image pixel = 1 screen pixel). Only visible tiles plus about one screen ahead in the scroll direction (half behind) are drawn. This also removes the old 8192 px cap, so high zoom on the 2300x3124 pages stays sharp.
- Every page first shows a quick low-res version (700 px) and the sharp tiles replace it. While zooming, the old tiles stretch until the new ones arrive. Pages never go missing.
- Cache is by memory (512 MB cap, least recently used goes first), not the old "wipe at 10 pages".
- Opening a 339-page book no longer loads every page first (sizes arrive in the background, scroll position is kept when they do).
- Thumbnails: only visible ones are made, in the background (they used to all render at open on the UI thread).
- Mouse-hover and selection no longer scan or copy a whole page of characters each frame (text and links for the current page are prepared when idle).
- Edits (pen, eraser, text, form fields): the visible tile is re-rendered at once so the change shows with no flicker (1 tile per frame), and the background copy refreshes a moment after you stop.
- perf.log next to ocr.log in %APPDATA%\LitePDF: one line per second while scrolling/zooming with frame max, gap between frames, upload times, render times, memory. Send it back and we see real frame times on your PC.
Tabs: tab strip under the menu (click to switch, x or middle-click to close, + to open in a new tab), every opened file gets its own tab (opening a file that is already open jumps to it), Ctrl+Tab / Ctrl+Shift+Tab switch, Ctrl+W closes, drag-and-drop a PDF onto the window to open it, unsaved-changes prompt (Save and close / Discard / Cancel). Each tab keeps its own page, zoom, selection, find results and edits. OCR belongs to the tab it was started in (its result goes back to that tab). Inactive tabs release their images (memory).
Kept: OCR, links, annotations, forms, signing, compress etc. unchanged.

VERIFIED HERE (Wine on a weak 2-core sandbox = proxy, not your PC; window/GPU not runnable here):
- Tile output matches a one-shot render: at 1.25x identical, at 3x max channel difference 2 of 255, zero pixels differing by more than 2 (no seams).
- Headless run of the real app logic (egui without a window) on a 339-page file: first frame 3.9 ms; page 0 sharp after ~190 ms; scrolling 200 frames: frame max ~5 ms, avg ~0.5 ms; pinch zoom 1.0 to 2.4x: frame max 1.5 ms; no blank top page during normal scroll; list replacement drops stale renders (wanted tile arrives ~100 ms after the change instead of waiting behind 28 others).
- Extreme scroll (160 px every 6 ms) shows white page placeholders about a third of the frames, because the sandbox cannot render that fast; your CPU is much faster but this is unmeasured.
- Tabs: open 3 files, switch (0.3 ms frame, sharp again ~210 ms on sandbox), scroll/rev kept per tab, close, reopen-already-open, close all: all behaved. Edit: change visible next frame, background copy refreshed ~0.7 s later. 
- Known cost: the edit frame takes ~70-100 ms on the sandbox at 2.4x zoom (one tile render on the UI thread); expect less on your CPU.

NOT VERIFIED (only your PC can show): that it actually feels as smooth as the Chromium viewer, real frame times, GPU texture upload cost with 1024 px tiles, HiDPI/monitor scale behaviour, Ctrl+Tab not being intercepted by Windows, drag-and-drop, the tab strip look, memory use with a real 339-page scan (cap 512 MB for images + the document held twice: once for the UI, once for the render thread), edit flicker on a real scan. OCR/DirectML adapter selection is NOT part of this build (still set litepdf.exe to High performance in Windows graphics settings).

Ask him to send perf.log after scrolling and zooming through the book for ~30 s; that settles whether it is smooth.
EOF
