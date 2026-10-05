cd /tmp/scratch/app/src; python3 - <<'PYEOF'
r=open('render.rs').read()
x="let area = mupdf::Rect { x0: rect.x0 as f32 / scale - 1.0, y0: rect.y0 as f32 / scale - 1.0, x1: rect.x1 as f32 / scale + 1.0, y1: rect.y1 as f32 / scale + 1.0 };"
assert x in r
r=r.replace(x,"// the scissor is in DEVICE space (after the ctm), not page units; page units wrongly culled most text and vector content when zoomed\n        let area = mupdf::Rect { x0: rect.x0 as f32 - 1.0, y0: rect.y0 as f32 - 1.0, x1: rect.x1 as f32 + 1.0, y1: rect.y1 as f32 + 1.0 };")
# catch panics per job
x="        let t = Instant::now();\n        match job.kind {"
assert x in r
r=r.replace(x,"        let t = Instant::now();\n        let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {\n        match job.kind {",1)
open('render.rs','w').write(r)
PYEOF
sed -n "$(grep -n 'let caught' render.rs | cut -d: -f1),+22p" render.rs | cut -c1-200
