cd /tmp/scratch; cp app/target/x86_64-pc-windows-gnu/release/litepdf.exe stage/litepdf.exe; export NSISDIR=/tmp/scratch/nsis-root/usr/share/nsis; export LD_LIBRARY_PATH=/tmp/scratch/nsis-root/usr/lib/x86_64-linux-gnu; nsis-root/usr/bin/makensis -V1 litepdf.nsi 2>&1|tail -3; unset LD_LIBRARY_PATH
I=LitePDF-Setup.exe; ls -l $I; sha256sum $I
head -c 16000000 $I > /downloads/LitePDF-Setup.exe.part1; tail -c +16000001 $I > /downloads/LitePDF-Setup.exe.part2; cat /downloads/LitePDF-Setup.exe.part1 /downloads/LitePDF-Setup.exe.part2 | sha256sum; ls -l /downloads/*.part*; sha256sum /downloads/*.part*
# silent install wine smoke
source wenv2.sh >/dev/null 2>&1; rm -rf inst; $WINE $I /S /D='Z:\tmp\scratch\inst' 2>&1|tail -1; ls inst
