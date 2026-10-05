cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
a=a.replace("if (awaiting || self.diag.sync_mode) && self.perf.sync_frame < 1 {","if self.perf.sync_frame < 1 {",1)
x="                if self.tile_missing(i, sk, *tx, *ty) {\n                    let t0"
assert x in a
a=a.replace(x,"                let stale = self.view.tiles.get(&i).and_then(|m| m.get(&(sk, *tx, *ty))).map_or(false, |t| t.rev < required);\n                if self.tile_missing(i, sk, *tx, *ty) && (awaiting || stale || self.diag.sync_mode) {\n                    let t0",1)
open('app.rs','w').write(a)
PYEOF
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head
