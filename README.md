# LitePDF

A small, fast PDF reader and editor for Windows, written in Rust. Native window, no browser engine, about 32 MB installed with OCR.

Stack: egui/eframe (OpenGL), MuPDF for rendering and PDF editing, ONNX Runtime with DirectML for OCR.

## Features

- Smooth scrolling and zoom. Zoom anchors on the pointer; touchpad pinch uses Windows Direct Manipulation.
- Document scrollbar with a page indicator.
- Full-resolution pages. Memory stays bounded (about 100 MB on large image-heavy files) because only pages near the view keep bitmaps and the PDF is read from disk.
- Tabs, find in document, page thumbnails, links, form fields.
- Annotate: highlight, underline, strikethrough, pen, text, eraser, redact, sign.
- Page tools: rotate, reorder, delete, compress.
- OCR for scanned PDFs (PaddleOCR models via ONNX Runtime).
- Convert (File > Convert): PDF to DOCX, PNG, JPEG, TXT, HTML; images to PDF. DOCX and HTML output is text-first, so complex layouts may reflow.

## Build

Rust stable with the `x86_64-pc-windows-gnu` target. MuPDF is vendored with a one-function patch (`shrink_store`) under `vendor/mupdf`.

    cargo build --release --target x86_64-pc-windows-gnu --bin litepdf

When cross-compiling from Linux, compile the C code and link with the same zig version; mixing versions breaks linking. The installer is built with NSIS from `litepdf.nsi`. It needs `litepdf.exe`, `DirectML.dll`, `onnxruntime.dll`, `onnxruntime_providers_shared.dll` and an `ocr` folder (`det.onnx`, `rec.onnx`, `dict.txt`).

## Command-line flags

- `--native-title`: use the Windows title bar instead of the custom one.
- `--dm=off`: disable Direct Manipulation touchpad handling and use the plain wheel path.

## Status

Releases are unsigned, so Windows SmartScreen may warn. Behaviour is verified on the author's Windows laptop only.

## Branches

`main` holds this app. An earlier Go prototype lives in the git history.
