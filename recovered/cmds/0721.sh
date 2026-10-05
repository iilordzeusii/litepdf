ls -d ~/.cargo/registry/src/*/mupdf-*; for d in ~/.cargo/registry/src/*/mupdf-*; do echo $d; grep -n 'clone_context\|new_context\|thread_local\|locks' $d/src/context.rs | head; done
