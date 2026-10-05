sleep 115; grep -E "^error|Finished" -A8 /tmp/scratch/h2.log | head -12 | cut -c1-200; tail -1 /tmp/scratch/h2.log | cut -c1-100
