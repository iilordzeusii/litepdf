cd /tmp/scratch/tess/bl; nohup sh -c 'make -j2 && make install' > /tmp/scratch/tess/bl.log 2>&1 &
sleep 90; tail -3 /tmp/scratch/tess/bl.log | cut -c1-200
