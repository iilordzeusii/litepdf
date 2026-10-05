cd /tmp/scratch; python3 - <<'E'
from PIL import Image
im=Image.open('/downloads/favicon-869cad8f-f0edac3f.ico'); print(im.info.get('sizes'), im.size)
for s in sorted(im.ico.sizes()): print(s)
E
/tmp/scratch/zig/zcc --version 2>&1 | head -2; ls /tmp/scratch/zig; python3 -c "import ziglang;print(ziglang.__file__)"; python3 -m ziglang version; which x86_64-w64-mingw32-windres windres llvm-rc 2>&1 | head
