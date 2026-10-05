cd /tmp/scratch/shot; ./target/release/shot ../t.pdf /tmp/s3.ppm 1.5 2>&1 | tail -2; python3 -c "
from PIL import Image; Image.open('/tmp/s3.ppm').save('/downloads/m3.png')"; (cd /tmp/scratch/app; source /tmp/scratch/wenv.sh; nohup cargo build --release --target x86_64-pc-windows-gnu > /tmp/scratch/winbuild3.log 2>&1 &); echo started
