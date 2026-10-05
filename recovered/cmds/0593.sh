cd /tmp; tools github get-file-content --owner iilordzeusii --repo focus-forge --path 4-index.html --json | jq -r .content > ff-index.html; wc -c ff-index.html; head -c 600 ff-index.html; grep -n -i -E 'pdf|canvas|worker' ff-index.html | head -30
python3 - <<'E'
import json
s=json.load(open('/tmp/z.json'))['content']
import re
print(len(s)); print(re.findall(r'[\w/.\-]+\.(?:ts|js|rs|html|css|json)',s)[:40])
E
