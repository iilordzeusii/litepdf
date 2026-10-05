cd /tmp/scratch/wt; python3 - <<'E'
from reportlab.pdfgen import canvas
c=canvas.Canvas("links.pdf")
c.drawString(100,700,"Contents: chapter 2 on page 3"); c.linkRect("","ch2",(95,690,300,715),relative=0)
c.drawString(100,650,"web link"); c.linkURL("https://example.com",(95,640,200,665),relative=0)
c.showPage(); c.drawString(100,700,"page2"); c.showPage()
c.bookmarkPage("ch2",fit="XYZ",top=500); c.drawString(100,700,"Chapter 2"); c.showPage(); c.save()
E
cd /tmp/scratch/app; cat >> src/bin/ocrcli.rs <<'E'
E
python3 - <<'E'
p='/tmp/scratch/app/src/bin/ocrcli.rs'
c=open(p).read()
c=c.replace("    let mut d = PdfDocument::open(&a[1]).unwrap();","""    if a.get(2).map(|s| s == "--links").unwrap_or(false) {
        let d = PdfDocument::open(&a[1]).unwrap();
        for i in 0..d.page_count().unwrap() { for l in d.load_page(i).unwrap().links().unwrap() {
            let dd = l.dest.or_else(|| d.resolve_link(&l.uri).ok().flatten());
            println!("page {} rect {:?} uri {:?} dest {:?}", i + 1, (l.bounds.x0, l.bounds.y0, l.bounds.x1, l.bounds.y1), l.uri, dd.map(|x| (x.loc.page_number, x.kind)));
        } }
        return;
    }
    let mut d = PdfDocument::open(&a[1]).unwrap();""",1)
open(p,'w').write(c)
E
source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu --bin ocrcli 2>&1 | grep -E "^error" -A12|head -30
cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1; cp /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/ocrcli.exe .; $WINE ocrcli.exe links.pdf --links 2>&1 | grep page
$WINE litepdf.exe --crashtest 2>&1 | tail -2; cat "/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF/crash.log" | head -8
