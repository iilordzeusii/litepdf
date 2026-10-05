cd /tmp/scratch; cp app/target/x86_64-pc-windows-gnu/release/litepdf.exe stage/litepdf.exe; file stage/litepdf.exe | cut -c1-90
NSISDIR=/tmp/scratch/nsis-root/usr/share/nsis /tmp/scratch/nsis-root/usr/bin/makensis -V1 litepdf.nsi 2>&1 | tail -2
cp stage/litepdf.exe /downloads/litepdf.exe; cp LitePDF-Setup.exe /downloads/; ls -la /downloads/*.exe
source wenv2.sh; export DISPLAY=:77 LIBGL_ALWAYS_SOFTWARE=1
timeout 25 $WINE stage/litepdf.exe 'Z:\tmp\scratch\t.pdf' 2>&1 | head -3
sha256sum /downloads/*.exe
