Target amd64-unicode
Unicode true
Name "LitePDF"
Icon "/home/sandbox/litepdf/recovered/app/icon.ico"
UninstallIcon "/home/sandbox/litepdf/recovered/app/icon.ico"
OutFile "/home/sandbox/LitePDF-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\LitePDF"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 64
Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles
Section "Install"
  SetOutPath $INSTDIR
  File "/home/sandbox/stage/litepdf.exe"
  File "/home/sandbox/stage/DirectML.dll"
  File "/home/sandbox/stage/onnxruntime.dll"
  File "/home/sandbox/stage/onnxruntime_providers_shared.dll"
  SetOutPath "$INSTDIR\ocr"
  File "/home/sandbox/stage/ocr/det.onnx"
  File "/home/sandbox/stage/ocr/rec.onnx"
  File "/home/sandbox/stage/ocr/dict.txt"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateDirectory "$SMPROGRAMS\LitePDF"
  CreateShortcut "$SMPROGRAMS\LitePDF\LitePDF.lnk" "$INSTDIR\litepdf.exe"
  CreateShortcut "$DESKTOP\LitePDF.lnk" "$INSTDIR\litepdf.exe"
  CreateShortcut "$SMPROGRAMS\LitePDF\LitePDF (compat touchpad).lnk" "$INSTDIR\litepdf.exe" "--dm=off"
  CreateShortcut "$SMPROGRAMS\LitePDF\LitePDF (native title bar).lnk" "$INSTDIR\litepdf.exe" "--native-title"
  WriteRegStr HKCU "Software\Classes\LitePDF.Document\shell\open\command" "" '"$INSTDIR\litepdf.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\.pdf\OpenWithProgids" "LitePDF.Document" ""
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LitePDF" "DisplayName" "LitePDF"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LitePDF" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LitePDF" "DisplayIcon" "$INSTDIR\litepdf.exe"
SectionEnd
Section "Uninstall"
  Delete "$INSTDIR\litepdf.exe"
  Delete "$INSTDIR\DirectML.dll"
  Delete "$INSTDIR\onnxruntime.dll"
  Delete "$INSTDIR\onnxruntime_providers_shared.dll"
  Delete "$INSTDIR\ocr\det.onnx"
  Delete "$INSTDIR\ocr\rec.onnx"
  Delete "$INSTDIR\ocr\dict.txt"
  RMDir "$INSTDIR\ocr"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\LitePDF\LitePDF.lnk"
  Delete "$SMPROGRAMS\LitePDF\LitePDF (compat touchpad).lnk"
  Delete "$SMPROGRAMS\LitePDF\LitePDF (native title bar).lnk"
  RMDir "$SMPROGRAMS\LitePDF"
  Delete "$DESKTOP\LitePDF.lnk"
  DeleteRegKey HKCU "Software\Classes\LitePDF.Document"
  DeleteRegValue HKCU "Software\Classes\.pdf\OpenWithProgids" "LitePDF.Document"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LitePDF"
SectionEnd
