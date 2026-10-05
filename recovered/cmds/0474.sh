tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Checkpoint (milestone build ready, not the final one). I stopped here because this run is near its time limit; zoom lag fix and tabs are NOT done yet.

DONE in this build (/tmp/scratch/LitePDF-Setup.exe, 31,088,784 bytes, SHA-256 e6fdc0640462806727c8d23203ea887ba41dd4d15056badd8b84f2a45705f96d; Drive upload NOT done yet):
1. PaddleOCR replaces Tesseract (details in my previous message). Installer lays down litepdf.exe, onnxruntime.dll, onnxruntime_providers_shared.dll, DirectML.dll, ocr\det.onnx, ocr\rec.onnx, ocr\dict.txt, and removes old Tesseract files on upgrade. Install tested under Wine (all files land).
2. Skip pages that already have text + "Re-OCR pages that already have text" checkbox. Tested (Wine).
3. Page box ("Page [n] / total", Enter jumps), filename and unsaved star in window title and toolbar. Compiles; the visuals are NOT checked (no GL under Wine).
4. Compression rework: now also handles JPEG scans (and ICC/Cal RGB/gray, not Indexed/CMYK/masked), resolution choice 100/150/200/300 dpi (scaled for A4-size scans), per-image check (replaced only if clearly smaller), whole file check (if the result is not smaller nothing is saved and the status says so), before/after KB in the status line. Tested here (Wine): a 300 dpi JPEG RGB scan 3,059 KB -> 398 KB at 150 dpi, 167 KB at 100 dpi; a JPEG gray scan 2,070 KB -> 340 KB / 146 KB. Not tested: a real ICCBased image, a real scanner PDF.
5. Icon: his favicon.ico is embedded as the exe icon (16, 32, 48 px), the window/taskbar icon, and the installer/uninstaller icon; shortcuts use the exe icon. The ICO has only 16, 32 and 48 px: NO 256 px size, so Explorer large-icon view upscales the 48 px one (a bit soft). Verified: the PE resource table of litepdf.exe and of the installer contains the icon group; I looked at the icon itself (blue rounded square, document with a magnifier). I did NOT see it rendered in Windows Explorer/taskbar (Wine has no shell).

VERIFIED here (CPU, Wine/Linux = proxy): OCR accuracy on a synthetic orange cover (12/12 words) and the paragraph scan (66 words), CPU fallback after DirectML fails, skip logic, compress numbers above.
ONLY HIS PC CAN CONFIRM: DirectML GPU path/speed on the RTX 3050, real DLL load (needs the VC++ runtime, nearly universal), window/title/page box look, icon in Explorer and taskbar.

STILL TO DO: zoom lag fix (real fix = render pages on a background thread; the current debounce is kept) and tabs. Question for you: ship this milestone to Drive now so he can test OCR/compress while I do zoom and tabs in a next run, or wait for the full build? Say which, and I will upload (Drive, anyone-with-link view) and report link, size, hash.
EOF
