# LitePDF

A small Windows PDF app: view, annotate, fill forms, merge, split, reorder/rotate/delete pages, compress, password and permissions, certificate signing, redaction, English OCR, and AI chat with your own Gemini or OpenRouter key.

Personal-use project. Licence: AGPL-3.0 (MuPDF is AGPL).

## How it is built

- Go shell: a local web server plus an Edge WebView2 window (WebView2 ships with Windows 10/11). If WebView2 is missing it opens your default browser instead.
- PDF engine: MuPDF compiled to WebAssembly (`mupdf` npm package).
- OCR: Tesseract.js with the English `tessdata_fast` model.
- Signing: `digitorus/pdfsign` (Go). Password and permission handling, compression and redaction use MuPDF.
- Web assets are gzipped and embedded in the single `litepdf.exe`.

## Build

Needs Go, Node 18+, and curl.

    sh build.sh        # fetches vendor files, writes litepdf.exe (Windows, amd64)

Tests (Linux or Windows with Node):

    pip install reportlab pillow && python3 test/make_sample.py
    node test/engine.test.mjs

## Use

- Redaction: draw boxes with "Mark redaction", or "Redact text..." to mark every match, then "Apply redactions". Applying removes the text and image pixels under the boxes. Undo works until you save.
- Compress: lossless, balanced (images up to 1800 px, JPEG 65) or strong (1100 px, JPEG 45). Images with transparency are left alone.
- OCR: replaces the page with its image plus an invisible text layer.
- Signing: pick a .pfx/.p12, or leave empty for a new self-signed certificate. Do not edit the PDF after signing.
- AI: click AI, then Key... Choose Gemini or OpenRouter, paste your key and a model id. The key is stored only in the app's local WebView storage and sent only to the provider through the local server. Document text (or the current page as an image) is sent to the provider when you ask.

## Known limits

- Signatures are invisible (no stamp on the page yet).
- Editing existing body text is not supported (annotation, forms, redaction only).
- OCR is English only, and the first run takes a moment to load the engine.
