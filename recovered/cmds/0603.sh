cd /tmp; r=$(tools cloud_browser_scheduler acquire --task-description='read private focus-forge zip' --mode=read --json); echo $r; echo $r > lease.json
L=$(jq -r .lease_id lease.json); T=$(jq -r .tab_id lease.json)
tools cloud_browser navigate --lease-id $L --tab-id $T --url https://github.com/iilordzeusii/focus-forge/blob/main/1-focus-forge-v1.6.2.zip --json
tools cloud_browser execute-js --lease-id $L --tab-id $T --script 'const r=await fetch("/iilordzeusii/focus-forge/raw/main/1-focus-forge-v1.6.2.zip",{credentials:"include"});const b=await r.arrayBuffer();window.__b=b;return {status:r.status,size:b.byteLength,url:r.url,ct:r.headers.get("content-type"),title:document.title}' --json
