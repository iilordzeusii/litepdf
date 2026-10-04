#!/bin/sh
# Copies the third-party runtime files into web/vendor (not committed to git).
set -e
cd "$(dirname "$0")/.."
npm install --no-audit --no-fund
mkdir -p web/vendor/ocr
cp node_modules/mupdf/dist/mupdf.js node_modules/mupdf/dist/mupdf-wasm.js node_modules/mupdf/dist/mupdf-wasm.wasm web/vendor/
cp node_modules/tesseract.js/dist/tesseract.min.js node_modules/tesseract.js/dist/worker.min.js web/vendor/ocr/
cp node_modules/tesseract.js-core/tesseract-core-simd-lstm.wasm.js web/vendor/ocr/
[ -f web/vendor/ocr/eng.traineddata ] || curl -sL -o web/vendor/ocr/eng.traineddata https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata
ls -l web/vendor web/vendor/ocr
