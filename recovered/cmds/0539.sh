cd /tmp; python3 - <<'E'
import json
d=json.load(open('/observations/chat-sessions/chat-01M42BRM3XS8YSRFDXMGYQEEH9/artifacts/toolu_01Mka151EvmUEFQ6acivtbbs.json'))
print(type(d), str(d)[:300])
E
