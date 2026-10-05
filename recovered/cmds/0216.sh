cd /tmp/scratch/app; ls ~/.cargo/registry/src/*/ | grep -i "windows_x86_64_gnu\|windows-targets"; cat > /tmp/scratch/zig/zcc <<'EOF'
#!/bin/bash
a=(); for x in "$@"; do case "$x" in
 --target=*) ;;
 -l:lib*.a|-lmsvcrt|-lmingw32|-lmingwex|-lgcc|-lgcc_eh|-lpthread) ;;
 -lwinapi_*) a+=("-l${x#-lwinapi_}");;
 -lwindows*) n=${x#-l}; f=$(ls ~/.cargo/registry/src/*/windows_x86_64_gnu-*/lib/lib$n.a 2>/dev/null | head -1); if [ -n "$f" ]; then a+=("$f"); else a+=("$x"); fi;;
 *) a+=("$x");; esac; done
exec python3 -m ziglang cc -target x86_64-windows-gnu "${a[@]}"
EOF
source /tmp/scratch/wenv.sh; timeout 100 cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E "^error|Finished|unable|undefined" | head -6 | cut -c1-200; ls -la target/x86_64-pc-windows-gnu/release/litepdf.exe
