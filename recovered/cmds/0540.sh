cd /tmp/scratch/ocrdl; for f in det.onnx rec.onnx; do echo $f; head -c 3000 $f | strings -n 3 | head -12; done; (pip install -q onnx 2>&1|tail -1; python3 - <<'E'
import onnx
for n in ("det.onnx","rec.onnx"):
    m=onnx.load(n)
    for i in m.graph.input: print(n,i.name,[d.dim_param or d.dim_value for d in i.type.tensor_type.shape.dim])
    for o in m.graph.output: print(n,'out',o.name,[d.dim_param or d.dim_value for d in o.type.tensor_type.shape.dim])
E
) 2>&1 | tail -8
