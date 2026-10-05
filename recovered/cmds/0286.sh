mkdir -p /tmp/scratch/tess && cd /tmp/scratch/tess; (curl -sL -o lept.zip https://github.com/DanBloomberg/leptonica/archive/refs/tags/1.87.0.zip; curl -sL -o tess.zip https://github.com/tesseract-ocr/tesseract/archive/refs/tags/5.5.2.zip; unzip -q lept.zip; unzip -q tess.zip; ls; ls -la *.zip | awk '{print $5,$9}')
cat > tc.cmake <<'EOF'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER /tmp/scratch/zig/zcc)
set(CMAKE_CXX_COMPILER /tmp/scratch/zig/zcxx)
set(CMAKE_AR /tmp/scratch/zig/zar)
set(CMAKE_RC_COMPILER "")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
EOF
echo "11:21 tesseract cross-build scratch at /tmp/scratch/tess (leptonica 1.87.0 + tesseract 5.5.2 sources, tc.cmake toolchain w/ zig). Plan: build tesseract CLI static for windows as bundled helper." >> ~/NOTES_native.md
