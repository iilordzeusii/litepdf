echo "11:48 final exe (GUI subsystem) + setup rebuilt, in /downloads. Wine: setup/uninstall ok; exe window can't open (no GL). Remaining: repo push via browser (source /tmp/scratch/app + shot test bins not needed; keep v1 tag), startup/RAM only on his PC" >> ~/NOTES_native.md
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/litepdf.exe /downloads/LitePDF-Setup.exe --message-stdin <<'EOF'
Build candidate for Aryan to test on his PC (native Rust, egui + MuPDF). Attached: litepdf.exe (15.0 MB, GUI app, no console) and LitePDF-Setup.exe (20.5 MB: per-user install, Start Menu and desktop shortcut, .pdf "Open with" entry, uninstaller, bundled English OCR). SHA-256 litepdf.exe 3b1a8f5c..., setup da91956d....

Ran on Linux/Wine only (not real Windows):
- Installer: silent install under Wine puts the files, shortcut and registry entries in place; uninstall removes the folder. Bundled tesseract.exe from the install folder read the test page correctly.
- Engine (host, checked with pypdf/qpdf/pdftotext/pyHanko): selection (drag, word, line), copy, highlight/underline/strike, ink, FreeText, eraser, true redaction, merge, split, reorder, delete, compress (5 MB to 149 KB on a noise test file), AES-256 password + permissions, certificate signing (valid, tamper detected), form fill (text + checkbox), OCR text layer without page growth.
- UI layout rendered on a CPU software renderer (screenshot sent earlier: toolbar, thumbnails, annotations, form widgets).
- AI: request/response for both providers checked against a local mock only; the key goes via stdin to curl, not the command line. Needs curl, which ships with Windows 10/11.

NOT verified (needs his PC): the window actually opening (Wine has no OpenGL), sharpness/HiDPI, pinch/trackpad zoom, live pen, on-page text box feel, menu/dialog flows and the Windows file pickers, AI with real keys, form-field click editing in the live UI, find behaviour live, OCR from the menu inside the app, signing from the menu. Startup time and RAM are not measured: the only honest numbers need real Windows. Sizes above are real. Known gap: OCR words may lose the space between some words ("Pageone."); not re-tested after my tweak. API key is stored in plain text in %APPDATA%\LitePDF\settings.json (UI says so).

Repo push (iilordzeusii/litepdf, replace v1, keep v1 tag) is NOT done yet. It needs the cloud-browser flow, which will take most of a run, so I'd do it after he confirms the app launches. Source is in /tmp/scratch/app, notes in ~/NOTES_native.md. Tell me whether to push now or wait for his test.
EOF
