cd /tmp/scratch/app/src && cat >> ops.rs <<'EOF'

#[derive(Clone, Debug)]
pub struct Field { pub xref: i32, pub rect: Rect, pub kind: mupdf::pdf::WidgetType, pub value: String, pub readonly: bool }

pub fn fields(doc: &PdfDocument, page: i32) -> Vec<Field> {
    let mut v = vec![];
    if let Ok(p) = doc.load_pdf_page(page) {
        for w in p.widgets() {
            let (Ok(k), Ok(x)) = (w.r#type(), w.xref()) else { continue };
            let r = w.annotation().rect().unwrap_or(Rect::new(0.0, 0.0, 0.0, 0.0));
            v.push(Field { xref: x, rect: r, kind: k, value: w.value().ok().flatten().unwrap_or_default(), readonly: w.is_readonly().unwrap_or(false) });
        }
    }
    v
}
pub fn set_field(doc: &mut PdfDocument, page: i32, xref: i32, val: &str) -> Result<bool, Error> {
    let p = doc.load_pdf_page(page)?;
    let Some(mut w) = p.load_widget(xref)? else { return Ok(false) };
    let ok = w.set_value(doc, val, false)?;
    w.update()?;
    Ok(ok)
}
pub fn toggle_field(doc: &mut PdfDocument, page: i32, f: &Field) -> Result<bool, Error> {
    let on = !(f.value.is_empty() || f.value == "Off");
    set_field(doc, page, f.xref, if on { "Off" } else { "Yes" })
}
EOF
cat >> /tmp/scratch/shot/src/bin/q.rs <<'EOF'
EOF
cat > /tmp/scratch/shot/src/bin/formtest.rs <<'EOF'
#[path = "/tmp/scratch/app/src/ops.rs"]
mod ops;
use mupdf::pdf::PdfDocument;
fn main(){
    let mut d = PdfDocument::open("/tmp/scratch/t.pdf").unwrap();
    let fs = ops::fields(&d, 0);
    for f in &fs { println!("{:?} {:?} val={:?} ro={}", f.xref, f.kind, f.value, f.readonly); }
    for f in &fs {
        match f.kind {
            mupdf::pdf::WidgetType::Text => println!("set text {:?}", ops::set_field(&mut d,0,f.xref,"Zeus Test")),
            mupdf::pdf::WidgetType::Checkbox => println!("toggle {:?}", ops::toggle_field(&mut d,0,f)),
            _=>{}
        }
    }
    for f in ops::fields(&d,0) { println!("after {:?} val={:?}", f.kind, f.value); }
    ops::save(&d, "/tmp/scratch/o_form.pdf", false).unwrap();
}
EOF
cd /tmp/scratch/shot; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 100 cargo build --release --bin formtest 2>&1 | grep -E "^error" -A8 | head -30; ./target/release/formtest; python3 -c "
import pypdf;r=pypdf.PdfReader('/tmp/scratch/o_form.pdf');print({k:v.get('/V') for k,v in r.get_fields().items()})"
