cd /tmp/scratch; python3 - <<'EOF'
s=open('litepdf.nsi').read()
s=s.replace('Section "Install"\n','''Function .onInit
  ReadRegStr $0 HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\LitePDF" "InstallLocation"
  StrCmp $0 "" +2 0
  StrCpy $INSTDIR $0
FunctionEnd
Section "Install"
  ; upgrade in place: a running litepdf.exe can be renamed, so the new file can be written
  IfFileExists "$INSTDIR\\litepdf.exe" 0 +3
  Delete "$INSTDIR\\litepdf.exe.old"
  Rename "$INSTDIR\\litepdf.exe" "$INSTDIR\\litepdf.exe.old"
''',1)
s=s.replace('''  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\LitePDF" "DisplayName" "LitePDF"''','''  Delete /REBOOTOK "$INSTDIR\\litepdf.exe.old"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\LitePDF" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\LitePDF" "DisplayName" "LitePDF"''',1)
s=s.replace('  Delete "$INSTDIR\\litepdf.exe"\n  Delete "$INSTDIR\\ocr','  Delete "$INSTDIR\\litepdf.exe"\n  Delete "$INSTDIR\\litepdf.exe.old"\n  Delete "$INSTDIR\\ocr',1)
open('litepdf.nsi','w').write(s)
EOF
NSISDIR=/tmp/scratch/nsis-root/usr/share/nsis /tmp/scratch/nsis-root/usr/bin/makensis -V1 litepdf.nsi 2>&1 | tail -3
source wenv2.sh; export DISPLAY=:77
rm -rf wp/drive_c/LitePDFtest2
for i in 1 2; do timeout 100 $WINE LitePDF-Setup.exe /S /D='C:\LitePDFup' 2>&1|tail -1; sleep 2; done
find wp/drive_c/LitePDFup -type f | sort; grep -c "InstallLocation" wp/user.reg; ls wp/drive_c/users/sandbox/Desktop | head
timeout 60 $WINE wp/drive_c/LitePDFup/uninstall.exe /S 2>&1|tail -1; sleep 3; ls wp/drive_c/LitePDFup 2>&1|head -2
