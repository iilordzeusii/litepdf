cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; D="/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF"; rm -f "$D"/*.log
timeout 100 $WINE ocrcli.exe book.pdf book_o.pdf 2>&1 | grep -E "^words"; grep -E "timing|memory" "$D/ocr.log" | cut -c1-260
cd /tmp/scratch; cp app/target/x86_64-pc-windows-gnu/release/litepdf.exe stage/litepdf.exe; export NSISDIR=/tmp/scratch/nsis-root/usr/share/nsis; export LD_LIBRARY_PATH=/tmp/scratch/nsis-root/usr/lib/x86_64-linux-gnu; nsis-root/usr/bin/makensis -V1 litepdf.nsi 2>&1|tail -2; unset LD_LIBRARY_PATH
I=LitePDF-Setup.exe; ls -l $I stage/litepdf.exe; sha256sum $I stage/litepdf.exe
head -c 16000000 $I > /downloads/LitePDF-Setup.exe.part1; tail -c +16000001 $I > /downloads/LitePDF-Setup.exe.part2; cat /downloads/LitePDF-Setup.exe.part1 /downloads/LitePDF-Setup.exe.part2 | sha256sum; ls -l /downloads/*.part*; sha256sum /downloads/*.part*
