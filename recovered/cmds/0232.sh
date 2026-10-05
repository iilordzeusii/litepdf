sleep 100; grep -E "^error|Finished" -A8 /tmp/scratch/h1.log | head -12 | cut -c1-200; tail -1 /tmp/scratch/h1.log | cut -c1-100
