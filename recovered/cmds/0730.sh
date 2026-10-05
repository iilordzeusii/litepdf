source /tmp/scratch/wenv2.sh; cd /tmp/scratch/wt; for f in book_o.pdf; do timeout 100 $WINE rendcli.exe $f 2>&1 | grep -E 'pool vs|scale|failed|panick' | head; done
