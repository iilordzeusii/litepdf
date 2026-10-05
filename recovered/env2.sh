source ~/tc/env.sh
Z=$HOME/tc/zig-linux-x86_64-0.13.0/lib
export RUSTFLAGS="-L native=$(ls -d ~/.cargo/registry/src/*/winapi-x86_64-pc-windows-gnu-0.4.0/lib)" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native BINDGEN_EXTRA_CLANG_ARGS="-I$HOME/hdr -I$Z/libc/include/any-windows-any -I$Z/libc/include/x86_64-windows-gnu -I$Z/libc/mingw/include --target=x86_64-pc-windows-gnu"
