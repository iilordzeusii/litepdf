cd /tmp/scratch/ocrdl; B=https://huggingface.co/Kreuzberg/paddleocr-onnx-models/resolve/main
curl -sL $B/manifest.json | head -c 1500; echo
for f in v2/det/mobile.onnx v2/rec/en_mobile/model.onnx v2/rec/en_mobile/dict.txt v2/cls/model.onnx; do mkdir -p $(dirname $f); curl -sL -m 60 -o $f $B/$f; done; ls -laR v2 | grep -v "^total"
curl -sL -m 60 -o dirml.nupkg https://api.nuget.org/v3-flatcontainer/microsoft.ai.directml/1.15.4/microsoft.ai.directml.1.15.4.nupkg; unzip -l dirml.nupkg | grep x64
pip download onnxruntime==1.22.1 --no-deps -d whl -q 2>&1 | tail -2; ls whl
