cd /tmp/scratch/app/src; grep -n "threads\|available_parallelism\|optimization\|GraphOpt" ocr.rs extras.rs | head -20; sed -n 45,58p ocr.rs
