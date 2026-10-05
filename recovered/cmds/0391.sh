cd /tmp/scratch/app/src && python3 - <<'EOF'
e=open('extras.rs').read()
a=e.index("    pub fn switch_to"); b=e.index("fn settings_path()")
e=e[:a]+'''    pub fn switch_to(&mut self, new: &str) {
        if self.provider == new { return; }
        let old = self.provider.clone();
        let loaded = self.saved.iter().position(|(p, _, _)| p == new).map(|i| self.saved.remove(i));
        self.saved.retain(|(p, _, _)| *p != old);
        self.saved.push((old, std::mem::take(&mut self.key), std::mem::take(&mut self.model)));
        if let Some((_, k, m)) = loaded { self.key = k; self.model = m; }
        self.provider = new.to_string();
    }
}
'''+e[b:]
open('extras.rs','w').write(e)
s=open('app.rs').read()
def rep(old,new):
    global s
    assert old in s, old[:70]
    s=s.replace(old,new,1)
rep('ui.horizontal(|ui| { ui.label("Provider"); egui::ComboBox::from_id_salt("prov").selected_text(self.settings.provider.clone()).show_ui(ui, |ui| { ui.selectable_value(&mut self.settings.provider, "Gemini".into(), "Gemini"); ui.selectable_value(&mut self.settings.provider, "OpenRouter".into(), "OpenRouter"); }); });',
'''ui.horizontal(|ui| { ui.label("Provider"); let mut sel = self.settings.provider.clone();
                    egui::ComboBox::from_id_salt("prov").selected_text(sel.clone()).show_ui(ui, |ui| { ui.selectable_value(&mut sel, "Gemini".into(), "Gemini"); ui.selectable_value(&mut sel, "OpenRouter".into(), "OpenRouter"); });
                    if sel != self.settings.provider { extras::save_settings(&self.settings); self.settings.switch_to(&sel); extras::save_settings(&self.settings); } });''')
# unique snapshot + commit helpers
a=s.index("    fn snapshot(&mut self)"); b=s.index("    pub fn poll(")
s=s[:a]+'''    fn snapshot(&mut self) -> Option<String> {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        let t = self.tmp(&format!("snap{}.pdf", N.fetch_add(1, Ordering::SeqCst)));
        match self.doc.as_ref().map(|d| ops::save(d, &t, false)) { Some(Ok(_)) => Some(t), Some(Err(e)) => { self.status = format!("Snapshot failed: {e}"); None } None => None }
    }
    /// Move a finished temp file to its final path. If that path is the open document, release the file first, replace it, then reopen.
    fn commit_file(&mut self, tmp: &str, out: &str) -> Result<(), String> {
        let same = !self.path.is_empty() && std::path::Path::new(&self.path) == std::path::Path::new(out);
        let keep = (self.scroll, self.zoom);
        if same { self.doc = None; }
        let moved = std::fs::rename(tmp, out).or_else(|_| std::fs::copy(tmp, out).map(|_| ()).and_then(|_| std::fs::remove_file(tmp)));
        if same {
            let src = if moved.is_ok() { out.to_string() } else { tmp.to_string() };
            match PdfDocument::open(&src) { Ok(d) => { self.set_doc(d); self.scroll = keep.0; self.zoom = keep.1; self.dirty = moved.is_err(); } Err(e) => return Err(format!("reopen failed: {e}")) }
        }
        moved.map_err(|e| format!("could not write {out}: {e}"))
    }
    fn save_inplace(&mut self, p: &str) {
        let tmp = format!("{p}.litepdf-tmp");
        let r = match self.doc.as_ref() { Some(d) => ops::save(d, &tmp, false).map_err(|e| e.to_string()), None => return };
        if let Err(e) = r { let _ = std::fs::remove_file(&tmp); self.status = format!("Save failed: {e}"); return; }
        self.path = p.to_string();
        match self.commit_file(&tmp, p) { Ok(_) => { self.dirty = false; self.status = format!("Saved {p}"); } Err(e) => self.status = format!("Save failed: {e}") }
    }
'''+s[b:]
rep('''        if let Some(d) = &self.doc { match ops::save(d, p, false) { Ok(_) => { self.path = p.to_string(); self.dirty = false; self.status = format!("Saved {p}"); } Err(e) => self.status = format!("Save failed: {e}") } }''','''        self.save_inplace(p);''')
# menus: remove merge/split
rep('            if ui.button("Merge with other PDFs...").clicked() { self.dlg = Dlg::Merge; ui.close(); }\n            if ui.button("Split...").clicked() { self.f1 = "1-1".into(); self.dlg = Dlg::Split; ui.close(); }\n','')
# compress
old=s[s.index('if let Some(out) = pick_save("compressed.pdf")'):]
old=old[:old.index("close = true;")]
new='''if let Some(out) = pick_save("compressed.pdf") { if let Some(snap) = self.snapshot() {
                            let tmpo = format!("{out}.litepdf-tmp");
                            match ops::compress(&snap, &tmpo, 1600, self.quality as u8) { Ok((a, b)) => { let (s0, s1) = (std::fs::metadata(&snap).map(|m| m.len()).unwrap_or(0), std::fs::metadata(&tmpo).map(|m| m.len()).unwrap_or(0));
                                match self.commit_file(&tmpo, &out) { Ok(_) => self.status = format!("Compressed {a}/{b} images: {} KB to {} KB, saved {out}", s0 / 1024, s1 / 1024), Err(e) => self.status = format!("Compress failed: {e}") } } Err(e) => { let _ = std::fs::remove_file(&tmpo); self.status = format!("Compress failed: {e}") } }
                            let _ = std::fs::remove_file(&snap); } }
                        '''
s=s.replace(old,new,1)
# protect
old=s[s.index('match ops::encrypt(&snap, &out, &self.f1, &owner, p)'):]
old=old[:old.index("close = true;")]
new='''let tmpo = format!("{out}.litepdf-tmp");
                            match ops::encrypt(&snap, &tmpo, &self.f1, &owner, p) { Ok(_) => match self.commit_file(&tmpo, &out) { Ok(_) => self.status = format!("Encrypted (AES-256) and saved {out}"), Err(e) => self.status = format!("Encrypt failed: {e}") }, Err(e) => { let _ = std::fs::remove_file(&tmpo); self.status = format!("Encrypt failed: {e}") } }
                            let _ = std::fs::remove_file(&snap); } }
                        '''
s=s.replace(old,new,1)
# sign
old=s[s.index('match extras::sign_pdf(&snap, &self.f1, &self.f2, &out, &self.f3)'):]
old=old[:old.index("self.f2.clear(); close = true;")]
new='''let tmpo = format!("{out}.litepdf-tmp");
                            match extras::sign_pdf(&snap, &self.f1, &self.f2, &tmpo, &self.f3) { Ok(_) => match self.commit_file(&tmpo, &out) { Ok(_) => self.status = format!("Signed and saved {out}"), Err(e) => self.status = e }, Err(e) => { let _ = std::fs::remove_file(&tmpo); self.status = e } }
                            let _ = std::fs::remove_file(&snap); } }
                        '''
s=s.replace(old,new,1)
# purge old temp on start
rep("    pub fn new() -> Self {\n","    pub fn new() -> Self {\n        if let Ok(rd) = std::fs::read_dir(std::env::temp_dir()) { for e in rd.flatten() { let n = e.file_name().to_string_lossy().to_string(); if n.starts_with(\"litepdf-\") && (n.ends_with(\".pdf\") || n.ends_with(\".bmp\") || n.ends_with(\".json\")) { let _ = std::fs::remove_file(e.path()); } } }\n",1)
open('app.rs','w').write(s)
EOF
cd /tmp/scratch/shot; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 100 cargo build --release --bin shot 2>&1 | grep -E "^error" -A12 | head -60 | cut -c1-190
