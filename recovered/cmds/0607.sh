cd /tmp; L=$(jq -r .lease_id lease.json); T=1
tools cloud_browser execute-js --lease-id $L --tab-id $T --script 'let s="";const u=window.__b;for(let i=0;i<u.length;i+=8192)s+=String.fromCharCode.apply(null,u.subarray(i,i+8192));return btoa(s)' --json | jq -r '.structured // .content' > b64.txt; head -c 60 b64.txt; echo; python3 - <<'E'
import json,base64,re
t=open('/tmp/b64.txt').read().strip()
try: t=json.loads(t) if t.startswith('"') else t
except: pass
open('/tmp/ff.zip','wb').write(base64.b64decode(t))
E
mkdir -p ff && cd ff && unzip -o -q ../ff.zip && find . -type f | xargs wc -c
