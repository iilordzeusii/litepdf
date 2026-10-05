cd /tmp/scratch/ocrdl; python3 - <<'E'
import onnx
for n in ("det.onnx","rec.onnx"):
    m=onnx.load(n)
    for i in m.graph.input: print(n,i.name,[d.dim_param or d.dim_value for d in i.type.tensor_type.shape.dim])
    for o in m.graph.output: print(n,'out',o.name,[d.dim_param or d.dim_value for d in o.type.tensor_type.shape.dim])
E
grep -n "fn with_dimension_override\|fn with_optimization_level\|with_dimension" ~/.cargo/registry/src/*/ort-2.0.0-rc.10/src/session/builder/*.rs | head; ls /tmp/scratch/ocrdl/ | head; sed -n 1,3p /tmp/scratch/app/NOTES 2>/dev/null; python3 -c "import cpuinfo" 2>&1|tail -1; nproc
