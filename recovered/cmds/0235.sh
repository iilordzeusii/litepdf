cd /tmp/scratch/shot; source ~/.cargo/env; echo "host shot build also needs BINDGEN_EXTRA_CLANG_ARGS=-I/usr/lib/gcc/x86_64-linux-gnu/11/include" >> ~/NOTES_native.md
RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native nohup cargo build --release > /tmp/scratch/h2.log 2>&1 &
sleep 105; grep -E "^error|Finished" -A8 /tmp/scratch/h2.log | head -10 | cut -c1-200; tail -1 /tmp/scratch/h2.log | cut -c1-100
