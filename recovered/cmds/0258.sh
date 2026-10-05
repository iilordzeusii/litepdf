cd /tmp/scratch/app/src && cat > ops.rs <<'EOF'
//! Document-level operations (merge, split, reorder, delete, rotate, compress, encrypt, redact). Pure MuPDF.
use mupdf::pdf::{PdfDocument, PdfWriteOptions, Encryption, Permission};
use mupdf::Error;

const INH: [&str; 4] = ["Resources", "MediaBox", "CropBox", "Rotate"];

fn page_objs(doc: &PdfDocument, idx: &[usize]) -> Result<Vec<mupdf::pdf::PdfObject>, Error> {
    let mut out = vec![];
    for &i in idx {
        let mut p = doc.find_page(i as i32)?;
        for k in INH {
            if p.get_dict(k)?.is_none() {
                if let Some(v) = p.get_dict_inheritable(k)? { p.dict_put(k, v)?; }
            }
        }
        out.push(p);
    }
    Ok(out)
}

/// Keep only `order` pages (in that order). Used for delete, reorder and split.
pub fn keep_pages(doc: &mut PdfDocument, order: &[usize]) -> Result<(), Error> {
    let mut pages = doc.catalog()?.get_dict("Pages")?.ok_or(Error::InvalidArgument("no Pages".into()))?;
    let objs = page_objs(doc, order)?;
    let mut kids = doc.new_array()?;
    for mut p in objs {
        p.dict_put("Parent", pages.clone())?;
        kids.array_push(p)?;
    }
    pages.dict_put("Kids", kids)?;
    pages.dict_put("Count", doc.new_int(order.len() as i32)?)?;
    Ok(())
}

/// Append all pages of `src` to `dst`.
pub fn append(dst: &mut PdfDocument, src: &PdfDocument) -> Result<(), Error> {
    let n = src.page_count()? as usize;
    let mut gm = dst.new_graft_map()?;
    let mut pages = dst.catalog()?.get_dict("Pages")?.ok_or(Error::InvalidArgument("no Pages".into()))?;
    let mut kids = pages.get_dict("Kids")?.ok_or(Error::InvalidArgument("no Kids".into()))?;
    let objs = page_objs(src, &(0..n).collect::<Vec<_>>())?;
    let mut added = 0;
    for p in objs {
        let mut g = gm.graft_object(&p)?;
        g.dict_put("Parent", pages.clone())?;
        kids.array_push(dst.add_object(&g)?)?;
        added += 1;
    }
    let cnt = pages.get_dict("Count")?.map(|c| c.as_int().unwrap_or(0)).unwrap_or(0);
    pages.dict_put("Count", dst.new_int(cnt + added)?)?;
    Ok(())
}

pub fn save(doc: &PdfDocument, out: &str, compact: bool) -> Result<(), Error> {
    let mut o = PdfWriteOptions::default();
    if compact { o.set_garbage_level(3); o.set_compress(true); o.set_clean(true); }
    doc.save_with_options(out, o)
}

pub fn merge(inputs: &[&str], out: &str) -> Result<(), Error> {
    let mut d = PdfDocument::open(inputs[0])?;
    for p in &inputs[1..] { let s = PdfDocument::open(*p)?; append(&mut d, &s)?; }
    save(&d, out, true)
}

pub fn split_ranges(input: &str, ranges: &[(usize, usize)], out_prefix: &str) -> Result<Vec<String>, Error> {
    let mut outs = vec![];
    for (k, (a, b)) in ranges.iter().enumerate() {
        let mut d = PdfDocument::open(input)?;
        let order: Vec<usize> = (*a..=*b).collect();
        keep_pages(&mut d, &order)?;
        let name = format!("{out_prefix}_{}.pdf", k + 1);
        save(&d, &name, true)?;
        outs.push(name);
    }
    Ok(outs)
}

pub fn reorder(input: &str, order: &[usize], out: &str) -> Result<(), Error> {
    let mut d = PdfDocument::open(input)?;
    keep_pages(&mut d, order)?;
    save(&d, out, true)
}

pub fn encrypt(input: &str, out: &str, user_pw: &str, owner_pw: &str, perms: Permission) -> Result<(), Error> {
    let d = PdfDocument::open(input)?;
    let mut o = PdfWriteOptions::default();
    o.set_encryption(Encryption::Aes256);
    o.set_user_password(user_pw);
    o.set_owner_password(owner_pw);
    o.set_permissions(perms);
    d.save_with_options(out, o)
}

pub fn decrypt(input: &str, password: &str, out: &str) -> Result<(), Error> {
    let mut d = PdfDocument::open(input)?;
    if d.needs_password()? { if !d.authenticate(password)? { return Err(Error::InvalidArgument("wrong password".into())); } }
    let mut o = PdfWriteOptions::default();
    o.set_encryption(Encryption::None);
    d.save_with_options(out, o)
}
EOF
cd /tmp/scratch/shot; mkdir -p src/bin; cat > src/bin/optest.rs <<'EOF'
#[path = "/tmp/scratch/app/src/ops.rs"]
mod ops;
use mupdf::{Document, pdf::{PdfDocument, Permission}};
fn text(p: &str) -> String { let d = Document::open(p).unwrap(); let mut s = String::new(); for i in 0..d.page_count().unwrap() { let pg = d.load_page(i).unwrap(); s += &format!("[p{}:{}] ", i, pg.to_text_page(mupdf::TextPageFlags::empty()).unwrap().to_text().unwrap().replace('\n', " ").chars().take(40).collect::<String>()); } s }
fn main() {
    let a = std::env::args().nth(1).unwrap();
    println!("src: {}", text(&a));
    ops::merge(&[&a, &a], "/tmp/scratch/o_merge.pdf").unwrap();
    println!("merge pages={} {}", Document::open("/tmp/scratch/o_merge.pdf").unwrap().page_count().unwrap(), text("/tmp/scratch/o_merge.pdf"));
    ops::reorder(&a, &[2, 0, 1], "/tmp/scratch/o_re.pdf").unwrap();
    println!("reorder: {}", text("/tmp/scratch/o_re.pdf"));
    let v = ops::split_ranges(&a, &[(0, 0), (1, 2)], "/tmp/scratch/o_split").unwrap();
    for f in &v { println!("split {f}: {}", text(f)); }
    ops::encrypt(&a, "/tmp/scratch/o_enc.pdf", "userpw", "ownerpw", Permission::PRINT).unwrap();
    let mut e = PdfDocument::open("/tmp/scratch/o_enc.pdf").unwrap();
    println!("enc needs_password={} auth_wrong={} auth_ok={}", e.needs_password().unwrap(), e.authenticate("bad").unwrap(), e.authenticate("userpw").unwrap());
    ops::decrypt("/tmp/scratch/o_enc.pdf", "userpw", "/tmp/scratch/o_dec.pdf").unwrap();
    println!("decrypt: {}", text("/tmp/scratch/o_dec.pdf"));
}
EOF
source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin optest 2>&1 | grep -E "^error|Finished" -A9 | head -50 | cut -c1-180)
