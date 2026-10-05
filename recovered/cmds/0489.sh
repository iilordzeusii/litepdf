cat >> ~/NOTES_native.md <<'EOF'

## 2026-10-04 7:33PM status
- PaddleOCR (src/ocr.rs, ort 2.0.0-rc.10 load-dynamic+directml) replaced Tesseract. Test crate /tmp/scratch/ocrt (host, LD=/tmp/scratch/ocrdl/lin/.../libonnxruntime.so.1.22.1, raw images .raw). Wine tests: /tmp/scratch/wt (ocrcli.exe, compcli.exe; needs bcryptprimitives.dll + zlib1.dll stubs in dir).
- Done: skip-text+force, page box, title/toolbar filename, compress rework, icon (app/icon.o via zig rc, build.rs), installer 31MB (stage/ has dlls+ocr models; litepdf.nsi updated).
- Drive upload blocked (tool cap 25MB; browser profiles not signed in). Waiting on parent.
- TODO: zoom lag (bg render thread), tabs. Final installer then rebuild with makensis (NSISDIR=/tmp/scratch/nsis-root/usr/share/nsis LD_LIBRARY_PATH=nsis-root/usr/lib/x86_64-linux-gnu).
EOF
