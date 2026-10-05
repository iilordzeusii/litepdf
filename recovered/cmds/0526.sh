cd /tmp/scratch/stage; ls -l litepdf.exe; sha256sum litepdf.exe; ls -l ocr; strings -n 8 litepdf.exe | grep -c "WORKER ENDED EARLY"
