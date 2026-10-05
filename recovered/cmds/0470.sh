cd /tmp/scratch/app; python3 - <<'E'
t=open('src/app.rs').read()
t=t.replace("} else\n                                match self.commit_file(&tmpo, &out) {","} else {\n                                match self.commit_file(&tmpo, &out) {",1)
t=t.replace('Err(e) => self.status = format!("Compress failed: {e}") } } Err(e) => { let _ = std::fs::remove_file(&tmpo);','Err(e) => self.status = format!("Compress failed: {e}") } } } Err(e) => { let _ = std::fs::remove_file(&tmpo);',1)
open('src/app.rs','w').write(t)
E
source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E "^error|Finished" -A8 | head -30
