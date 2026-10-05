sleep 80; grep -E "^error|Finished" -A6 /tmp/scratch/winbuild3.log | head; pgrep cargo|head -1
