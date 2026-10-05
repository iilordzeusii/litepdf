cd /tmp/scratch; export WINEPREFIX=/tmp/wp WINEDEBUG=-all; export DISPLAY=:99; (pgrep Xvfb >/dev/null || (Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &)); sleep 1
rm -rf /tmp/wp/drive_c/users/*/AppData/Local/Programs/LitePDF 2>/dev/null
time timeout 100 wine /downloads/LitePDF-Setup.exe /S /D=C:\\LitePDFtest 2>&1 | tail -3; sleep 2
find /tmp/wp/drive_c/LitePDFtest -type f | xargs ls -la; file /downloads/litepdf.exe | cut -c1-120
cd /tmp/wp/drive_c/LitePDFtest; (timeout 20 wine litepdf.exe /tmp/scratch/t.pdf 2>&1 | head -5)
