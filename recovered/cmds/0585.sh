tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Noted: target is "snappy, clean, extremely high res, no scroll lag". The plan I just sent already aims at that; two additions so that bar is met on resolution too:
- Resolution: v1 rasterised at zoom x devicePixelRatio (capped at 2, app.js line 7) and showed that bitmap 1:1. In the egui app the render scale is zoom x pixels-per-point (capped at an 8192 px side), so sharpness is equivalent, but while a new zoom level renders the old texture is stretched (blurry for a moment). With the background worker the blur window drops from "frozen" to ~50-150 ms. I will keep an idle sharpening pass: after 200 ms of no input render the visible pages at 1.0x of the screen pixels (already the case) and keep 1 extra "supersample" tier only for the page being read at high zoom if memory allows.
- No-lag bar: the unit of success is "no frame over 16-20 ms during scroll and zoom". The perf.log in the plan reports max frame time per second, so we can check this on his PC with numbers instead of feel.
Nothing else changes in the plan. Waiting for his go; I will not build before that.
EOF
