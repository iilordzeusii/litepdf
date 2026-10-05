cd /tmp/scratch/app; (timeout 300 python3 -m ziglang rc /:output-format coff /:target x86_64 icon.rc icon.o > /tmp/rc.log 2>&1 &); sleep 40; cat /tmp/rc.log; ls -la icon.o 2>&1
