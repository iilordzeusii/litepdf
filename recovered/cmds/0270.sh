cd /tmp/scratch; pdftotext -raw o_red.pdf - 2>/dev/null | head -3; python3 - <<'EOF'
import subprocess
s=subprocess.run(["qpdf","--qdf","--object-streams=disable","o_red.pdf","-"],capture_output=True).stdout.decode('latin1')
i=s.find("BT"); print(s[i:i+600])
EOF
mutool draw -F txt o_red.pdf 1 2>/dev/null | head -3; which mutool
