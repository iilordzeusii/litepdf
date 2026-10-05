cd /tmp; L=$(jq -r .lease_id lease.json); T=1
tools cloud_browser execute-js --lease-id $L --tab-id $T --script 'const r=await fetch("/iilordzeusii/focus-forge/raw/main/1-focus-forge-v1.6.2.zip",{credentials:"include"});const b=await r.arrayBuffer();window.__b=b;return {status:r.status,size:b.byteLength,url:r.url}' --json | head -c 500
