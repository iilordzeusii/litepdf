cd /tmp/scratch/app/src; sed -n 1,36p bin/rendcli.rs | cut -c1-220; cd /tmp/scratch/wt; for f in *.pdf; do printf '%s ' $f; python3 - "$f" <<'PYEOF'
import sys,re
d=open(sys.argv[1],'rb').read()
print(len(d), 'Image' , d.count(b'/Subtype/Image')+d.count(b'/Subtype /Image'), 'Link', d.count(b'/Link'), 'Font', d.count(b'/Font'))
PYEOF
done
