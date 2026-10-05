cd /tmp/scratch; python3 - <<'EOF'
import pypdf
r=pypdf.PdfReader('o_annot.pdf'); p=r.pages[1]
for a in p.get('/Annots',[]):
    a=a.get_object(); print(a.get('/Subtype'), a.get('/Contents',''), [round(float(x)) for x in a.get('/Rect',[])])
EOF
pdftoppm -r 80 -f 2 -l 2 -png o_annot.pdf an >/dev/null 2>&1; cp an-2.png /downloads/an.png; echo "11:34 annotation helpers (highlight/underline/strike/ink/freetext/eraser) in ops.rs verified via pypdf+mupdf (annotest bin)" >> ~/NOTES_native.md
