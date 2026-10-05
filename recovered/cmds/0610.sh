cd /tmp; L=$(jq -r .lease_id lease.json); tools cloud_browser_scheduler release --lease-id $L; tools help browser_guidance.record | grep -E '^\s+--' | head -12
