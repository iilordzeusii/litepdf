cd /tmp/scratch/shot; python3 - <<'EOF'
s=open('src/main.rs').read()
s=s.replace("let mut last = None;","let mut last = None; let mut sets = vec![];")
s=s.replace("        last = Some((jobs, o.textures_delta));","        sets.extend(o.textures_delta.set.clone());\n        last = Some((jobs, o.textures_delta));")
s=s.replace("let (jobs, td) = last.unwrap();","let (jobs, mut td) = last.unwrap(); td.set = sets;")
open('src/main.rs','w').write(s)
EOF
sleep 45; grep -E "^error|Finished" -A6 /tmp/scratch/h1.log | head -8 | cut -c1-160; tail -1 /tmp/scratch/h1.log | cut -c1-100
