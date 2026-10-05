cd /tmp/scratch; python3 - <<'E'
from PIL import Image
im=Image.open('/downloads/favicon-869cad8f-f0edac3f.ico'); im=im.convert('RGBA')
bg=Image.new('RGBA',(48*4+20,48*4+20),(70,70,70,255)); bg.paste(im.resize((192,192),Image.NEAREST),(10,10),im.resize((192,192),Image.NEAREST)); bg.save('/downloads/icon_preview.png')
im.save('/tmp/scratch/app/icon48.png'); open('/tmp/scratch/app/icon48.rgba','wb').write(im.tobytes()); print(im.size, im.getpixel((24,24)), im.getpixel((0,0)))
E
