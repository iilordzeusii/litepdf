cd /tmp/scratch/sg; ./target/release/sg ../t.pdf signer.p12 pw ../o_signed.pdf 2>&1 | tail -6; python3 - <<'EOF'
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko.sign.validation import validate_pdf_signature
from pyhanko_certvalidator import ValidationContext
r=PdfFileReader(open('/tmp/scratch/o_signed.pdf','rb'))
for s in r.embedded_signatures:
    st=validate_pdf_signature(s, ValidationContext(allow_fetching=False))
    print(s.field_name, 'intact=',st.intact,'valid=',st.valid,'coverage=',st.coverage, 'trusted=',st.trusted)
EOF
