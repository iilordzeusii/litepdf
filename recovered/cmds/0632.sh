cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh; timeout 100 $WINE rendcli.exe book.pdf 2>&1 | grep -v fixme | tail -15
