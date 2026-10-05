cp /tmp/scratch/LitePDF-Setup.exe /downloads/; sha256sum /downloads/LitePDF-Setup.exe | cut -c1-16
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-Setup.exe --message-stdin <<'EOF'
Final-candidate report 1/2 (installer attached; the exe comes in a second message because of the 20 MB attachment cap). LitePDF-Setup.exe is 20.4 MB: per-user install, Start Menu + desktop shortcut, .pdf "Open with" entry, uninstaller, bundled English OCR (tesseract + eng data). The same litepdf.exe is also inside it (15.0 MB, GUI app, native Rust, egui + MuPDF).

Ran on Linux/Wine only (not real Windows):
- Installer: silent install under Wine places files, shortcut and registry entries; uninstall removes the folder. Bundled tesseract.exe from the install folder read the test page correctly.
- Engine (host, checked with pypdf/qpdf/pdftotext/pyHanko): selection (drag, word, line), copy, highlight/underline/strike, ink, FreeText, eraser, true redaction, merge, split, reorder, delete, compress (5 MB to 149 KB on a noise test file), AES-256 password + permissions, certificate signing (valid, tamper detected), form fill (text + checkbox), OCR text layer with page size unchanged.
- UI layout rendered on a CPU software renderer (screenshot sent earlier).
- AI: request/response for both providers checked against a local mock only; key goes via stdin to curl (ships with Windows 10/11), not the command line.

NOT verified (needs his PC): the window opening (Wine has no OpenGL), sharpness/HiDPI, pinch/trackpad zoom, live pen, on-page text box feel, menu/dialog flows and Windows file pickers, AI with real keys, form-field click editing in the live UI, live find, OCR and signing from the menus. Startup time and RAM are NOT measured (only real Windows gives honest numbers). Sizes are real. Known gap: OCR may drop the space between some words ("Pageone."). API key is stored in plain text in %APPDATA%\LitePDF\settings.json (the UI says so).

Repo push (iilordzeusii/litepdf, replace v1, keep v1 tag) is NOT done; it needs the browser flow and I would do it after he confirms the app launches. Source: /tmp/scratch/app; notes: ~/NOTES_native.md. Tell me push now or wait.
EOF
tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/litepdf.exe --message-stdin <<'EOF'
Report 2/2: standalone litepdf.exe (15.0 MB, same build as inside the installer; portable, but OCR needs the installer's ocr folder next to it). SHA-256 3b1a8f5c606d1584eabbac7e165d489cf2092e8681ad351007422df9e556c564.
EOF
