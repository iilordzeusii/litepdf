cd /tmp/scratch; python3 - <<'EOF' 2>&1 | tail -2
d=bytearray(open('o_signed.pdf','rb').read()); i=d.find(b'Page one'); 
# tamper inside original content region (find a text byte in uncompressed region if any), else flip a byte near start of file body
j=d.find(b'obj',100)+20; d[j]^=1; open('o_tamper.pdf','wb').write(d)
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko.sign.validation import validate_pdf_signature
from pyhanko_certvalidator import ValidationContext
try:
    r=PdfFileReader(open('o_tamper.pdf','rb'))
    for s in r.embedded_signatures:
        st=validate_pdf_signature(s, ValidationContext(allow_fetching=False)); print('tampered intact=',st.intact,'valid=',st.valid)
except Exception as e: print('tampered: rejected', type(e).__name__)
EOF
echo "11:20 SIGNING VERIFIED: underskrift pure-Rust PAdES signs t.pdf; pyHanko: intact=True valid=True coverage=ENTIRE_FILE (untrusted only since self-signed). Needs tokio rt (blocking). Pure Rust -> no Go helper needed." >> ~/NOTES_native.md
