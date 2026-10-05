cd /tmp/scratch/tess/bt; make tesseract 2>&1 | grep -E "error|undefined" | head -5 | cut -c1-240; cat CMakeFiles/tesseract.dir/link.txt | tr ' ' '\n' | grep -E "^-l|\.lib|\.a$" | head
