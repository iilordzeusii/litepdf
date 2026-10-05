source /tmp/scratch/wenv.sh; cd /tmp && (rustc --version; ls ~/.cargo/bin | head -3); rustc -O zt.rs -o zt 2>&1 | head -3 ; ./zt
