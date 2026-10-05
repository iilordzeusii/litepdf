cd /tmp/scratch; python3 - <<'E'
s=open('litepdf.nsi').read()
s=s.replace('''  SetOutPath "$INSTDIR\\ocr"
  File "/tmp/scratch/stage/ocr/tesseract.exe"
  SetOutPath "$INSTDIR\\ocr\\tessdata"
  File "/tmp/scratch/stage/ocr/tessdata/eng.traineddata"
''','''  ; old Tesseract files from earlier builds
  Delete "$INSTDIR\\ocr\\tesseract.exe"
  Delete "$INSTDIR\\ocr\\tessdata\\eng.traineddata"
  RMDir "$INSTDIR\\ocr\\tessdata"
  File "/tmp/scratch/stage/onnxruntime.dll"
  File "/tmp/scratch/stage/onnxruntime_providers_shared.dll"
  File "/tmp/scratch/stage/DirectML.dll"
  SetOutPath "$INSTDIR\\ocr"
  File "/tmp/scratch/stage/ocr/det.onnx"
  File "/tmp/scratch/stage/ocr/rec.onnx"
  File "/tmp/scratch/stage/ocr/dict.txt"
''')
s=s.replace('''  Delete "$INSTDIR\\ocr\\tesseract.exe"
  Delete "$INSTDIR\\ocr\\tessdata\\eng.traineddata"
  RMDir "$INSTDIR\\ocr\\tessdata"
  RMDir "$INSTDIR\\ocr"
  Delete "$INSTDIR\\uninstall.exe"''','''  Delete "$INSTDIR\\onnxruntime.dll"
  Delete "$INSTDIR\\onnxruntime_providers_shared.dll"
  Delete "$INSTDIR\\DirectML.dll"
  Delete "$INSTDIR\\ocr\\det.onnx"
  Delete "$INSTDIR\\ocr\\rec.onnx"
  Delete "$INSTDIR\\ocr\\dict.txt"
  RMDir "$INSTDIR\\ocr"
  Delete "$INSTDIR\\uninstall.exe"''')
open('litepdf.nsi','w').write(s)
E
grep -n "tess" litepdf.nsi; rm -rf stage/ocr; mkdir -p stage/ocr; cp ocrdl/{det.onnx,rec.onnx,dict.txt} stage/ocr/; cp ocrdl/win/*.dll stage/; cd app; source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E "^error|Finished" -A6; cp target/x86_64-pc-windows-gnu/release/litepdf.exe /tmp/scratch/stage/; which makensis; ls ~/ | head -0
