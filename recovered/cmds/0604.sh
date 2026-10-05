cd /tmp; L=$(jq -r .lease_id lease.json); T=1
tools cloud_browser navigate --lease-id $L --tab-id $T --url https://github.com/iilordzeusii/focus-forge --wait-until none --json; sleep 5
tools cloud_browser execute-js --lease-id $L --tab-id $T --script '({u:location.href,t:document.title,login:!!document.querySelector("meta[name=user-login]")&&document.querySelector("meta[name=user-login]").content})' --json
