cd /tmp/scratch/app; cp /downloads/favicon-869cad8f-f0edac3f.ico icon.ico; echo '1 ICON "icon.ico"' > icon.rc; python3 -m ziglang rc /? 2>&1 | head -25
