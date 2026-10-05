cd /tmp/scratch/app/src; python3 - <<'PYEOF'
r=open('render.rs').read()
x="                } else { let _ = tx.send(Res::JobFailed { job, why: \"render returned nothing (page load or pixmap failure)\" }); wake(&ctx); }\n            }\n        }\n    }\n}"
assert x in r
r=r.replace(x,"                } else { let _ = tx.send(Res::JobFailed { job, why: \"render returned nothing (page load or pixmap failure)\" }); wake(&ctx); }\n            }\n        }\n        }));\n        if caught.is_err() { let _ = tx.send(Res::JobFailed { job, why: \"render thread panicked (font or engine error)\" }); wake(&ctx); }\n    }\n}",1)
open('render.rs','w').write(r)
PYEOF
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 110 cargo build --release --target x86_64-pc-windows-gnu --bin rendcli 2>&1 | grep -E '^error' -A8 | head -30; source /tmp/scratch/wenv2.sh; cd /tmp/scratch/wt; cp /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/rendcli.exe .; timeout 100 $WINE rendcli.exe vec.pdf 2>&1 | grep -v fixme | head -14
