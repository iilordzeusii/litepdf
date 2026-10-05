cd /tmp/scratch/tess; grep -rn "FMEMOPEN" leptonica-1.87.0 --include=*.txt --include=*.cmake --include=*.h --include=*.in | head -8; sed -n 1945,1953p leptonica-1.87.0/src/boxbasic.c
