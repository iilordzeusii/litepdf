cd /tmp; for q in "DirectML execution provider cache compiled graph between sessions EP context model DML" "ONNX Runtime free dimension override DirectML batch size performance PaddleOCR recognition fixed width"; do echo "=== $q"; tools web_search --query "$q" --limit 5 --json | jq -r '.[] | "\(.url)\n  \(.highlights[0:2]|join(" | ")|.[0:380])"'; done; python3 - <<'E'
import json
d=json.load(open('/observations/chat-sessions/chat-01M42BRM3XS8YSRFDXMGYQEEH9/artifacts/toolu_01Mka151EvmUEFQ6acivtbbs.json'))
for r in d:
    if 'openvino' in str(r).lower() or 'quant' in r['url'].lower(): print(r['url'], str(r['highlights'])[:300])
E
