cd /tmp; python3 - <<'E'
import json,re
s=json.load(open('/tmp/z.json'))['content']
for k in ['pdfjs','getDocument','canvas','renderTask','devicePixelRatio','GlobalWorkerOptions','src/main.ts']:
    print(k,[m.start() for m in re.finditer(k,s)][:5])
E
tools github get-file-content --owner iilordzeusii --repo focus-forge --path 1-focus-forge-v1.6.2.zip --json | jq -r '.content|length'
tools github get-file-content --owner iilordzeusii --repo focus-forge --path .github --json 2>&1 | head -c 400
