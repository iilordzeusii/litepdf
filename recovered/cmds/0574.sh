f=/downloads/Untitled-f8946219.txt; head -40 $f | cut -c1-300; grep -n "adapters\|created\|CPU bench\|keeping\|switching" $f | cut -c1-250 | head -20; grep -n "timing" $f | sed -n 1,12p | cut -c1-300
