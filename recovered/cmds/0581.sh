cd /tmp/scratch/app/src; grep -n "for (i, r) in rects.iter().enumerate()" app.rs | head; awk 'NR>=432 && NR<=475' app.rs | cut -c1-260; sed -n 85,97p app.rs | cut -c1-260
