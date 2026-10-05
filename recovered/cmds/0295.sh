cd /tmp/scratch/tess/bt; nohup sh -c 'make -j2 tesseract' > /tmp/scratch/tess/bt.log 2>&1 & sleep 105; tail -2 /tmp/scratch/tess/bt.log | cut -c1-160
