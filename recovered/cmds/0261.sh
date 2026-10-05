cd /tmp/scratch; for f in t o_re o_merge; do echo "$f: $(pdftotext $f.pdf - 2>&1 >/dev/null | wc -l) warnings"; done
