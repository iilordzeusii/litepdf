sleep 110; grep -E "^error|Finished" -A6 /tmp/scratch/a1.log | head -20 | cut -c1-200; tail -1 /tmp/scratch/a1.log | cut -c1-100
