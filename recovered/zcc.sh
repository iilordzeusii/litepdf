#!/bin/bash
a=(); skip=0
for x in "$@"; do
  if [ $skip = 1 ]; then skip=0; continue; fi
  case "$x" in --target=*) ;; --target|-target) skip=1;; -l:lib*.a|-Wl,--disable-auto-image-base|-lmsvcrt|-lmingw32|-lmingwex|-lgcc|-lgcc_eh|-lpthread) ;; -lwindows.*) f=$(ls $HOME/.cargo/registry/src/*/windows_x86_64_gnu-*/lib/lib${x#-l}.a | head -1); a+=("$f");; -lwinapi_*) a+=("-l${x#-lwinapi_}");; *) a+=("$x");; esac
done
exec python3 -m ziglang cc -target x86_64-windows-gnu "${a[@]}"
