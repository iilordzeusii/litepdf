cd /tmp; L=$(jq -r .lease_id lease.json); T=1
tools cloud_browser execute-js --lease-id $L --tab-id $T --script 'const r=await fetch("/iilordzeusii/focus-forge/raw/main/1-focus-forge-v1.6.2.zip");const b=await r.arrayBuffer();window.__b=new Uint8Array(b);return {status:r.status,size:b.byteLength,url:r.url.slice(0,80)}' --json | head -c 500
