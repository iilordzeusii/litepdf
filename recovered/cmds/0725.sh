cd /tmp/scratch/wt; python3 - <<'PYEOF'
import random
random.seed(1)
N=60
objs=[]
def add(s): objs.append(s); return len(objs)
# 1 catalog,2 pages,3 font,4 font bold
add("<< /Type /Catalog /Pages 2 0 R >>")
add(None)
add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
add("<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>")
kids=[]
words="the quick brown fox jumps over lazy dog vector text rendering tile worker pool mupdf display list glyph cache".split()
for p in range(N):
    c=[]
    for ln in range(55):
        y=800-ln*14
        txt=" ".join(random.choice(words) for _ in range(12))
        c.append(f"BT /F{1+ln%2} {8+ln%4} Tf 40 {y} Td ({txt}) Tj ET")
    for k in range(30):
        x=random.randint(30,500);y=random.randint(30,780)
        c.append(f"{random.random():.2f} {random.random():.2f} {random.random():.2f} rg {x} {y} {random.randint(5,60)} {random.randint(3,30)} re f")
        c.append(f"0 0 0 RG {x} {y} m {x+random.randint(-80,80)} {y+random.randint(-80,80)} l S")
    st="\n".join(c)
    cid=add(f"<< /Length {len(st)} >>\nstream\n{st}\nendstream")
    pid=add(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents {cid} 0 R >>")
    kids.append(pid)
objs[1]=f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] /Count {N} >>"
out=b"%PDF-1.4\n"; offs=[]
for i,o in enumerate(objs):
    offs.append(len(out)); out+=f"{i+1} 0 obj\n{o}\nendobj\n".encode()
x=len(out)
out+=f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n".encode()
for o in offs: out+=f"{o:010d} 00000 n \n".encode()
out+=f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{x}\n%%EOF\n".encode()
open("vec.pdf","wb").write(out)
PYEOF
ls -l vec.pdf; cd /tmp/scratch/app/src; python3 - <<'PYEOF'
s=open('bin/rendcli.rs').read()
i=s.rindex("}")
s=s[:i]+'''    // 4. pool vs single thread, content comparison (vector text pages)
    {
        let np = n.min(60) as usize; let mut local: Vec<Option<mupdf::DisplayList>> = vec![];
        for p in 0..np { local.push(doc.load_page(p as i32).ok().and_then(|pg| pg.to_display_list(true).ok())); }
        let w2 = Worker::new();
        w2.send(Cmd::Open { tab: 7, epoch: 1, rev: 0, src: Src::Path(path.clone()), pw: None, want_sizes: true });
        let _ = w2.rx.recv_timeout(Duration::from_secs(60));
        for &s in &[1.0f32, 2.5] {
            let key = scale_key(s);
            let mut jobs = vec![]; let mut sizes = vec![];
            for p in 0..np { let pg = doc.load_page(p as i32).unwrap(); let b = pg.bounds().unwrap(); let sz = (b.x1 - b.x0, b.y1 - b.y0); sizes.push(sz); let (pw, ph) = page_px(sz, key_scale(key)); for ty in 0..((ph + TILE - 1) / TILE) { for tx in 0..((pw + TILE - 1) / TILE) { jobs.push(Job { tab: 7, epoch: 1, page: p, kind: Kind::Tile { key, tx: tx as u16, ty: ty as u16 } }); } } }
            let total = jobs.len(); w2.send(Cmd::Want(jobs));
            let (mut got, mut bad, mut fails) = (0usize, 0usize, 0usize); let mut firstbad = String::new();
            let t = Instant::now();
            while got + fails < total && t.elapsed() < Duration::from_secs(100) {
                match w2.rx.recv_timeout(Duration::from_secs(20)) {
                    Ok(Res::Img { job, rgba, wid, .. }) => { got += 1;
                        let l = local[job.page].as_ref().unwrap();
                        let (_, _, r2) = render_job_doc(l, sizes[job.page], job.kind).unwrap();
                        if r2 != rgba { bad += 1; if firstbad.is_empty() { firstbad = format!("page {} {:?} worker {}", job.page + 1, job.kind, wid); } } }
                    Ok(Res::JobFailed { job, why }) => { fails += 1; println!("job failed {:?}: {why}", job); }
                    Ok(_) => {}
                    Err(_) => break }
            }
            println!("pool vs single-thread at scale {s}: {total} tiles requested, {got} received, {fails} failed, {bad} differ {firstbad} ({:.0} ms)", t.elapsed().as_secs_f32() * 1000.0);
        }
    }
}
'''
open('bin/rendcli.rs','w').write(s)
PYEOF
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 110 cargo build --release --target x86_64-pc-windows-gnu --bin rendcli 2>&1 | grep -E '^error' -A8 | head -30
