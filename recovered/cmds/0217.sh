echo "10:03 litepdf.exe (egui M0 viewer) LINKS 10.8MB; zcc maps -lwindows.* to windows_x86_64_gnu .a. Next: wine run + screenshot" >> ~/NOTES_native.md; which import xwd scrot convert 2>&1 | head; cd /tmp/scratch; cp ~/pdfapp/test/out_annot.pdf t.pdf; cp app/target/x86_64-pc-windows-gnu/release/litepdf.exe . ; cp bcryptprimitives.dll .
cat > shot.sh <<'EOF'
W=/tmp/scratch/wineroot; export WINEPREFIX=/tmp/scratch/wp WINEARCH=win64 WINEDLLOVERRIDES="mscoree,mshtml=d;bcryptprimitives=n" LD_LIBRARY_PATH=$W/usr/lib/x86_64-linux-gnu:$W/usr/lib/x86_64-linux-gnu/wine WINESERVER=$W/usr/lib/wine/wineserver64 WINEDLLPATH=$W/usr/lib/x86_64-linux-gnu/wine
cd /tmp/scratch
Xvfb :77 -screen 0 1280x900x24 >/dev/null 2>&1 &
sleep 2; export DISPLAY=:77
$W/usr/lib/wine/wine64 litepdf.exe 'Z:\tmp\scratch\t.pdf' > run.log 2>&1 &
sleep 20
import -window root /tmp/scratch/m0.png 2>&1 || xwd -root -silent | convert xwd:- /tmp/scratch/m0.png
ps -o rss,etime,cmd -C litepdf.exe 2>/dev/null; ps aux | grep litepdf | head -3
kill %2 2>/dev/null; pkill -f wine64; kill %1
EOF
timeout 60 bash shot.sh 2>&1 | tail -5; grep -v fixme run.log | tail -5; ls -la m0.png
