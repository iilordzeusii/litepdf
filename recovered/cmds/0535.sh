cd /tmp; tools web_fetch --url https://onnxruntime.ai/docs/execution-providers/DirectML-ExecutionProvider.html --json > dml.json; jq -r '.[0] | keys' dml.json; python3 - <<'E'
import json,re
d=json.load(open('/tmp/dml.json'))
t=d[0].get('content') or d[0].get('text') or json.dumps(d[0])
i=t.find('Performance Tuning'); print(t[i:i+2600])
j=t.find('Disable',0); 
for m in re.finditer('memory pattern|parallel execution',t): print(t[max(0,m.start()-200):m.start()+300]); break
E
tools web_fetch --url https://github.com/microsoft/onnxruntime/issues/20983 --json | python3 -c "
import json,sys
d=json.load(sys.stdin); t=d[0].get('content',''); i=t.find('turns out'); print(t[i-200:i+1800])"
