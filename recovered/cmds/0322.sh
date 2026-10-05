cd /tmp/scratch/shot; grep -n "sim\|args" src/main.rs | head -30; ./target/release/shot ../t.pdf /tmp/s2.ppm 1.5 2>&1 | tail -3; python3 -c "
from PIL import Image; Image.open('/tmp/s2.ppm').save('/downloads/m2a.png')"
