cd /tmp/scratch; tools read --help 2>&1 | head -12; convert m0.png -resize 50% m0s.png; tools read m0s.png 2>&1 | head -5
