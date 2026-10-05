cd /tmp/scratch; python3 - <<'EOF'
import pefile
EOF
for f in tess/bt/bin/tesseract.exe stage/litepdf.exe; do echo == $f; strings -a $f | grep -iE '^[A-Za-z0-9_+-]+\.dll$' | sort -u | tr '\n' ' '; echo; done
