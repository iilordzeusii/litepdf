cd /tmp/scratch/ocrdl; wc -l v2/rec/en_mobile/dict.txt; head -c 200 v2/rec/en_mobile/dict.txt | tr '\n' '|'; echo; tail -c 60 v2/rec/en_mobile/dict.txt | od -c | tail -4; pip install -q whl/*.whl 2>&1 | tail -1; python3 - <<'E'
import onnxruntime as o
for f in ["v2/det/mobile.onnx","v2/rec/en_mobile/model.onnx"]:
    s=o.InferenceSession(f)
    print(f,[(i.name,i.shape) for i in s.get_inputs()],[(i.name,i.shape) for i in s.get_outputs()], s.get_modelmeta().description[:100])
E
mkdir -p lin && cd lin && unzip -oq ../whl/*.whl 'onnxruntime/capi/libonnxruntime*' && ls onnxruntime/capi; mkdir -p ../win && cd ../win && unzip -oj -q ../dml.zip 'runtimes/win-x64/native/*.dll' && unzip -oj -q ../dirml.nupkg 'bin/x64-win/DirectML.dll' && ls -la
