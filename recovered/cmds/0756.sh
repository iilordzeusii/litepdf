cd /downloads; tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin >/dev/null <<'EOF'
b11 report (installer parts follow in 2 messages). Joined SHA-256 d6621cf63c389521d81b9b062a97835925d5ef5dd0837a0cf8f2a492aae89cd6, 31,149,660 bytes (part1 16,000,000 + part2 15,149,660). Join: copy /b part1+part2 LitePDF-b11-Setup.exe. Repo not pushed.

SCROLL - verified from Chromium source (all HEAD):
- ui/events/blink/web_input_event_builders_win.cc: a Windows WM_MOUSEWHEEL is converted as ticks = delta/120, x 3 lines, x (100/3) px, so 100 px per 120 units. The file says outright: "we leave hasPreciseScrollingDeltas false, even for trackpad scrolls that generate WM_MOUSEWHEEL ... (crbug.com/545234)".
- ui/events/blink/web_input_event.cc MakeWebMouseWheelEvent: on Windows, an event carrying a native message uses that builder (not precise). Only events with no native message take the precise-pixel path.
- cc/input/input_handler.cc ShouldAnimateScroll: animated unless granularity is kScrollByPrecisePixel. So a Windows touchpad is ANIMATED in Chromium, same as a mouse wheel. The user was right that there is easing.
- cc/animation/scroll_offset_animation_curve.cc: cubic-bezier(0.42,0,0.58,1); kInverseDelta duration = clamp(14 - |delta|/60, 6, 12) / 60 s; UpdateTarget retargets with velocity preservation (EaseInOutBoundedSegmentDuration, velocity bound x2.5).
- scroll_offset_animation_curve_factory.cc: kMouseWheel -> kInverseDelta.
- Inertia: Chromium adds none for WM_MOUSEWHEEL. Any coasting after the fingers lift is extra wheel events sent by Windows, and the animation retargets on each one.
b11 removes both b10 deviations: a new animation starts at slope 0 (eases from rest, no first-frame jump) and the duration scale is 1.0 (Chromium's exact value). Diagnostics sliders still exist but default to 1.0.

WHY b10 FELT TOO FAST (honest): the distance formula was already Chromium's (delta x 100 px per tick). I could not find a distance bug. The likely cause is my two deviations (half duration plus an instant start slope), which made every swipe finish at twice the speed. I cannot prove that without his perf log. If b11 is still too fast, it is not the animation. Then the likely difference is Windows delivering touchpad deltas differently to LitePDF than to Chrome (see below), and the Diagnostics "Scroll distance" slider is the knob.

ZOOM jumpiness, cause: Windows delivers touchpad pinch to winit as ctrl+wheel steps, not a continuous gesture. b10 applied each step instantly (up to x1.25), so zoom moved in visible jumps. I did not measure the step size on his device; this is inferred from how the events arrive. Chromium's own zoom is continuous because Windows precision touchpads feed it DirectManipulation pinch events. LitePDF does not receive those through its window library. b11: ctrl+wheel steps (kept as Chromium's gesture_detector.ts scale = clamp(exp(dy/100), 0.75, 1.25)) are now eased in log space with a ~35 ms exponential approach. It starts on the first frame, anchored at the cursor. Real pinch or multitouch events are still applied directly. This smoothing is MY APPROXIMATION, not Chromium code. The +/- buttons still jump x1.25 (Chromium uses preset zoom steps, not copied).

Input-event caveat: LitePDF gets input through winit/egui, not Chromium's input stack. So the touchpad delta size and timing are whatever winit passes (WM_MOUSEWHEEL / 120 as line units, treated as the wheel path, matching the Chromium Windows path). Chromium's DirectManipulation pinch/pan path and any compositor-thread input are not reproduced.

Tests (Wine, proxy only): scroll, zoom, 6 stress rounds with 0 missing tiles, edit, and tabs all pass. Everything about feel, touchpad, GPU, and vsync is PC-only and unverified.
EOF
for n in 1 2; do tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-b11-Setup.part$n --message "LitePDF b11 installer part $n of 2. Joined SHA-256 d6621cf63c389521d81b9b062a97835925d5ef5dd0837a0cf8f2a492aae89cd6 (31,149,660 bytes). Join with: copy /b LitePDF-b11-Setup.part1+LitePDF-b11-Setup.part2 LitePDF-b11-Setup.exe" >/dev/null && echo sent $n; done
