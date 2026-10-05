tools web_search --query "PP-OCRv4 mobile det rec ONNX model size MB onnxruntime DirectML rust ort OCR" --limit 6 --json | python3 -c "
import json,sys
for r in json.load(sys.stdin)[:6]: print(r['url']); print(' ', ' '.join(r['highlights'])[:350].replace('\n',' '))"
tools web_search --query "Windows.Media.Ocr OcrEngine Rust windows crate TryCreateFromUserProfileLanguages recognize SoftwareBitmap" --limit 5 --json | python3 -c "
import json,sys
for r in json.load(sys.stdin)[:5]: print(r['url']); print(' ', ' '.join(r['highlights'])[:300].replace('\n',' '))"
tools web_search --query "oar-ocr OR paddle-ocr-rs rust crate PaddleOCR ONNX Runtime DirectML CUDA" --limit 5 --json | python3 -c "
import json,sys
for r in json.load(sys.stdin)[:5]: print(r['url']); print(' ', ' '.join(r['highlights'])[:300].replace('\n',' '))"
