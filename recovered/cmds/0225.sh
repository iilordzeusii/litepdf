grep -E "^error|panicked|stdout" -A6 /tmp/scratch/h1.log | head -25 | cut -c1-200
