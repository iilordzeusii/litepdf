cd /tmp/scratch; cp app/target/x86_64-pc-windows-gnu/release/litepdf.exe stage/litepdf.exe; export NSISDIR=/tmp/scratch/nsis-root/usr/share/nsis; export LD_LIBRARY_PATH=/tmp/scratch/nsis-root/usr/lib/x86_64-linux-gnu; nsis-root/usr/bin/makensis -V1 litepdf.nsi 2>&1 | tail -3; ls -la LitePDF-Setup.exe; unset LD_LIBRARY_PATH
source /tmp/scratch/wenv2.sh; export DISPLAY=:77; rm -rf /tmp/scratch/inst; timeout 90 $WINE LitePDF-Setup.exe /S /D='Z:\tmp\scratch\inst' 2>&1 | grep -v fixme | tail -2; find /tmp/scratch/inst -type f | head -20; sha256sum LitePDF-Setup.exe; python3 - <<'E'
import pefile
pe=pefile.PE('/tmp/scratch/LitePDF-Setup.exe'); print([ (e.name or pefile.RESOURCE_TYPE.get(e.struct.Id)) for e in pe.DIRECTORY_ENTRY_RESOURCE.entries])
E
