cd /tmp/scratch/app/src; cp app.rs /tmp/app.rs.b3; python3 - <<'PYEOF'
import re
s=open('app.rs').read()
def rep(a,b,cnt=1):
    global s
    assert s.count(a)>=1, a[:60]
    s=s.replace(a,b,cnt)

rep("use crate::{ops, extras};","use crate::{ops, extras, render};\nuse crate::render::{Cmd, Src, Res, Job, Kind, Worker};")
rep("use std::collections::HashMap;","use std::collections::{HashMap, HashSet};")
rep("Reload(String, String)","Reload(u32, String, String)")
rep("Merge, Ocr }","Merge, Ocr, CloseTab(usize) }")
# struct fields
rep("    pub tex: HashMap<(usize, u32), TextureHandle>,\n    pub thumbs: HashMap<usize, TextureHandle>,\n","    pub view: DocView,\n    pub worker: Option<Worker>,\n    pub frame: u64,\n    pub tabs: Vec<Option<DocState>>, pub active: usize, pub next_tab: u32,\n    pub last_sent: HashSet<Job>, pub want_bases: HashSet<usize>, pub doc_pw: Option<String>,\n    pub perf: Perf, pub prev_scroll: f32, pub scroll_vel: f32,\n")
rep("tex: HashMap::new(), thumbs: HashMap::new(), ","view: DocView::new(1, 0), worker: None, frame: 0, tabs: vec![None], active: 0, next_tab: 2, last_sent: HashSet::new(), want_bases: HashSet::new(), doc_pw: None, perf: Perf::new(), prev_scroll: 0.0, scroll_vel: 0.0, ")
# open/set_doc/invalidate/page_tex/thumb
a=s.index("    pub fn open(&mut self, p: &str) {")
b=s.index("    pub fn page_links(&mut self")
# keep a '#[cfg(windows)]' that precedes page_links? check
pre=s[b-30:b]
new_block='''    pub fn open(&mut self, p: &str) {
        if let Some(i) = self.find_tab(p) { self.switch_to(i); return; }
        match PdfDocument::open(p) {
            Ok(d) => {
                if self.doc.is_some() { self.new_tab_blank(); }
                if d.needs_password().unwrap_or(false) { self.pending = Some(d); self.pending_path = p.to_string(); self.f1.clear(); self.dlg = Dlg::Password; return; }
                self.set_doc_src(d, Some(p.to_string())); self.path = p.to_string(); self.dirty = false; self.status = format!("Opened {p}"); }
            Err(e) => self.status = format!("Open failed: {e}"),
        }
    }
    pub fn set_doc(&mut self, d: PdfDocument) { self.set_doc_src(d, None) }
    pub fn set_doc_src(&mut self, d: PdfDocument, path: Option<String>) {
        let n = d.page_count().unwrap_or(0).max(0) as usize;
        let s0 = d.load_page(0).ok().and_then(|p| p.bounds().ok()).map(|b| Vec2::new(b.x1 - b.x0, b.y1 - b.y0)).unwrap_or(vec2(595.0, 842.0));
        self.sizes = vec![s0; n];
        let pw = self.doc_pw.take();
        let src = match path { Some(p) => Src::Path(p), None => { let mut buf: Vec<u8> = vec![]; let _ = d.write_to(&mut buf); Src::Bytes(buf) } };
        self.doc = Some(d);
        self.links.clear(); self.text.clear(); self.sel = None; self.find_hits.clear(); self.find_for.clear();
        let epoch = self.view.epoch + 1; let tab = self.view.tab;
        self.view = DocView::new(tab, epoch); self.view.pw = pw.clone();
        self.last_sent.clear();
        self.worker().tx.send(Cmd::Open { tab, epoch, rev: 0, src, pw, want_sizes: true }).ok();
    }
    pub fn worker(&mut self) -> &Worker { if self.worker.is_none() { self.worker = Some(Worker::new()); } self.worker.as_ref().unwrap() }
    pub fn save_to(&mut self, p: &str) {
        self.save_inplace(p);
    }
    fn invalidate(&mut self, page: usize) {
        self.text.remove(&page); self.links.remove(&page); self.dirty = true;
        let pr = self.view.rev + 1; self.view.page_rev.insert(page, pr);
        self.view.refresh_due = Some(std::time::Instant::now() + std::time::Duration::from_millis(250));
    }
    fn invalidate_all(&mut self) {
        self.text.clear(); self.links.clear(); self.dirty = true;
        self.view.rev_all = self.view.rev + 1;
        self.view.refresh_due = Some(std::time::Instant::now() + std::time::Duration::from_millis(250));
    }
'''
s=s[:a]+new_block+s[b:]
rep("self.tex.clear(); self.thumbs.clear(); self.text.clear(); self.links.clear(); self.dirty = true;","self.invalidate_all();")
open('app.rs','w').write(s)
print(repr(pre))
PYEOF
grep -n 'self.tex\|self.thumbs\|page_tex\|thumb(' app.rs | cut -c1-140
