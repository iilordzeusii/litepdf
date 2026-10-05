cd /tmp/scratch; ls tess/*.bmp tess/*.png tess/*.pdf 2>/dev/null; python3 - <<'EOF'
import pypdf
r=pypdf.PdfReader('/tmp/o_ocr.pdf'); p=r.pages[0]
print(p['/Resources'].get('/Font'))
for k,v in (p['/Resources'].get('/Font') or {}).items(): print(k, v.get_object() if hasattr(v,'get_object') else v)
EOF
