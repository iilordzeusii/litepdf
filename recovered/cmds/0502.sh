cd /tmp/scratch/app/src; grep -n "fn nowin\|pub fn settings_path\|fn settings_path\|^use" extras.rs | head; grep -n "fn snapshot" -A6 app.rs | head -12; grep -n "pub fn save" -A8 ops.rs | head -14
