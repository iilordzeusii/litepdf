cd /tmp/scratch/app/src; sed -n 140,148p ocr.rs; sed -n 220,228p ocr.rs; grep -n "struct.*Word\|y: f\|h: f" ocr.rs extras.rs | head
