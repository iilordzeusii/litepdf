source /tmp/scratch/wenv2.sh; cd /tmp/scratch/wt; timeout 100 $WINE rendcli.exe vec.pdf 2>&1 | grep -v fixme | head -30
