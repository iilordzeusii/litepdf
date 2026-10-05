cd /tmp/scratch/app/src && grep -n "fn snapshot" -B1 -A5 app.rs; grep -n "fn save_to" -A4 app.rs; grep -n "save_cmd" app.rs | head; grep -n "Merge with other\|Split\.\.\." app.rs
