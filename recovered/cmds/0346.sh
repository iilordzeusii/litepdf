mkdir -p /tmp/scratch/stage/ocr/tessdata && cd /tmp/scratch/stage && cp ../app/target/x86_64-pc-windows-gnu/release/litepdf.exe . && cp ../tess/bt/bin/tesseract.exe ocr/ && cp ../tess/td/eng.traineddata ocr/tessdata/ && cat > ../litepdf.nsi <<'EOF'
Target amd64-unicode
Unicode true
Name "LitePDF"
OutFile "/tmp/scratch/LitePDF-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\LitePDF"
RequestExecutionLevel user
SetCompressor /SOLID lzma
Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles
Section "Install"
  SetOutPath $INSTDIR
  File "/tmp/scratch/stage/litepdf.exe"
  SetOutPath "$INSTDIR\ocr"
  File "/tmp/scratch/stage/ocr/tesseract.exe"
  SetOutPath "$INSTDIR\ocr\tessdata"
  File "/tmp/scratch/stage/ocr/tessdata/eng.traineddata"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateDirectory "$SMPROGRAMS\LitePDF"
  CreateShortcut "$SMPROGRAMS\LitePDF\LitePDF.lnk" "$INSTDIR\litepdf.exe"
  CreateShortcut "$DESKTOP\LitePDF.lnk" "$INSTDIR\litepdf.exe"
  WriteRegStr HKCU "Software\Classes\LitePDF.Document\shell\open\command" "" '"$INSTDIR\litepdf.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\.pdf\OpenWithProgids" "LitePDF.Document" ""
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LitePDF" "DisplayName" "LitePDF"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LitePDF" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LitePDF" "DisplayIcon" "$INSTDIR\litepdf.exe"
SectionEnd
Section "Uninstall"
  Delete "$INSTDIR\litepdf.exe"
  Delete "$INSTDIR\ocr\tesseract.exe"
  Delete "$INSTDIR\ocr\tessdata\eng.traineddata"
  RMDir "$INSTDIR\ocr\tessdata"
  RMDir "$INSTDIR\ocr"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\LitePDF\LitePDF.lnk"
  RMDir "$SMPROGRAMS\LitePDF"
  Delete "$DESKTOP\LitePDF.lnk"
  DeleteRegKey HKCU "Software\Classes\LitePDF.Document"
  DeleteRegValue HKCU "Software\Classes\.pdf\OpenWithProgids" "LitePDF.Document"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LitePDF"
SectionEnd
EOF
NSISDIR=/tmp/scratch/nsis-root/usr/share/nsis /tmp/scratch/nsis-root/usr/bin/makensis -V1 ../litepdf.nsi 2>&1 | tail -5; ls -la /tmp/scratch/LitePDF-Setup.exe; grep -n "fn main" -A12 /tmp/scratch/app/src/main.rs | head -30
