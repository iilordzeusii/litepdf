cd /tmp/scratch/app; sed -i '1i #![cfg_attr(windows, windows_subsystem = "windows")]' src/main.rs; echo "11:47 fix: exe was console subsystem -> added windows_subsystem attr, rebuilding then repackage installer" >> ~/NOTES_native.md; (source /tmp/scratch/wenv.sh; nohup cargo build --release --target x86_64-pc-windows-gnu > /tmp/scratch/winbuild2.log 2>&1 &)
cat > /tmp/scratch/wenv2.sh <<'EOF'
W=/tmp/scratch/wineroot; export WINEPREFIX=/tmp/scratch/wp WINEARCH=win64 WINEDLLOVERRIDES="mscoree,mshtml=d;bcryptprimitives=n" LD_LIBRARY_PATH=$W/usr/lib/x86_64-linux-gnu:$W/usr/lib/x86_64-linux-gnu/wine WINESERVER=$W/usr/lib/wine/wineserver64 WINEDLLPATH=$W/usr/lib/x86_64-linux-gnu/wine WINEDEBUG=-all
WINE=$W/usr/lib/wine/wine64
EOF
source /tmp/scratch/wenv2.sh; pgrep Xvfb >/dev/null || (Xvfb :77 -screen 0 1280x900x24 >/dev/null 2>&1 &); sleep 1; export DISPLAY=:77
timeout 100 $WINE /tmp/scratch/LitePDF-Setup.exe /S /D='C:\LitePDFtest' 2>&1 | tail -3; sleep 3; find /tmp/scratch/wp/drive_c/LitePDFtest -type f | xargs ls -la
