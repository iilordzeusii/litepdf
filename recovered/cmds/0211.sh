cat > /tmp/scratch/wenv.sh <<'EOF'
source ~/.cargo/env
Z=/usr/local/lib/python3.10/dist-packages/ziglang
export RUSTFLAGS="-L native=$(ls -d ~/.cargo/registry/src/*/winapi-x86_64-pc-windows-gnu-0.4.0/lib)" PATH=/tmp/scratch/zig:$PATH LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native CC_x86_64_pc_windows_gnu=/tmp/scratch/zig/zcc CXX_x86_64_pc_windows_gnu=/tmp/scratch/zig/zcxx AR_x86_64_pc_windows_gnu=/tmp/scratch/zig/zar CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=/tmp/scratch/zig/zcc BINDGEN_EXTRA_CLANG_ARGS="-I/tmp/scratch/hdr -I$Z/lib/libc/include/any-windows-any -I$Z/lib/libc/include/x86_64-windows-gnu -I$Z/lib/libc/mingw/include --target=x86_64-pc-windows-gnu"
export CARGO_TARGET_DIR=/tmp/scratch/app/target
EOF
echo "9:53 /tmp/scratch/wenv.sh = windows build env; app crate at /tmp/scratch/app (eframe0.31 glow + mupdf). build: source wenv.sh; cargo build --release --target x86_64-pc-windows-gnu" >> ~/NOTES_native.md
cd /tmp/scratch/app; source /tmp/scratch/wenv.sh; nohup cargo build --release --target x86_64-pc-windows-gnu > /tmp/scratch/a1.log 2>&1 &
sleep 100; grep -E "^error|Finished" -A6 /tmp/scratch/a1.log | head -20 | cut -c1-200; tail -1 /tmp/scratch/a1.log | cut -c1-100
