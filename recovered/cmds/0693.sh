cd /tmp/scratch/app/src; python3 - <<'PYEOF'
import re
a=open('app.rs').read()
def rep(x,y):
    global a
    assert x in a,x[:60]; a=a.replace(x,y,1)
rep("pub ai_scope_doc: bool,","pub ai_scope_doc: bool, pub ai_mode: u8, pub ai_from: String, pub ai_to: String,")
rep("ai_scope_doc: false,","ai_scope_doc: false, ai_mode: 0, ai_from: \"1\".into(), ai_to: String::new(),")
i=a.index('                ui.checkbox(&mut self.ai_use_text, "Send current page text");')
j=a.index("\n",i)
a=a[:i]+'''                ui.label("Pages sent to the AI");
                ui.horizontal(|ui| { for (m, t) in [(0u8, "Current page"), (1, "Page range"), (2, "Full doc")] { if ui.selectable_label(self.ai_mode == m, t).clicked() { self.ai_mode = m; } } });
                if self.ai_mode == 1 { ui.horizontal(|ui| { ui.label("from"); ui.add(egui::TextEdit::singleline(&mut self.ai_from).desired_width(50.0)); ui.label("to"); ui.add(egui::TextEdit::singleline(&mut self.ai_to).desired_width(50.0).hint_text("last")); }); }
                ui.checkbox(&mut self.ai_use_text, "Send page text"); ui.checkbox(&mut self.ai_use_image, "Send page images (one per page)");
                let pg = self.ai_pages();
                if let (Some(f), Some(l)) = (pg.first(), pg.last()) { ui.label(format!("Sending {} page{} (pages {}-{}){}", pg.len(), if pg.len() == 1 { "" } else { "s" }, f + 1, l + 1, if self.ai_use_image { format!(", text and {} image{}", pg.len(), if pg.len() == 1 { "" } else { "s" }) } else { String::new() })); } else { ui.label("Sending 0 pages"); }'''+a[j:]
rep("    fn ask_ai(&mut self) {","""    fn ai_pages(&self) -> Vec<usize> {
        ai_page_list(self.ai_mode, &self.ai_from, &self.ai_to, self.cur_page, self.sizes.len())
    }
    fn ask_ai(&mut self) {""")
rep("        if self.ai_use_text || self.ai_scope_doc {\n            let pages: Vec<usize> = if self.ai_scope_doc { (0..self.sizes.len()).collect() } else { vec![c] };","        let sel_pages = self.ai_pages();\n        if self.ai_use_text {\n            let pages: Vec<usize> = sel_pages.clone();")
i=a.index("        if self.ai_use_image { if let Some(d) = &self.doc { if let Ok(pg) = d.load_page(c as i32) {")
j=a.index("        let q = std::mem::take(&mut self.chat_input);")
a=a[:i]+'''        let mut imgs: Vec<String> = vec![];
        if self.ai_use_image { if let Some(d) = &self.doc { for &pi in &sel_pages { if let Ok(pg) = d.load_page(pi as i32) {
            if let Ok(pm) = pg.to_pixmap(&Matrix::new_scale(1.6, 1.6), &Colorspace::device_rgb(), false, true) {
                let mut jpg = vec![]; let enc = jpeg_encoder::Encoder::new(&mut jpg, 80);
                if enc.encode(pm.samples(), pm.width() as u16, pm.height() as u16, jpeg_encoder::ColorType::Rgb).is_ok() { imgs.push(b64(&jpg)); } } } } } }
        let _ = c; let _ = &mut img;
'''+a[j:]
rep("extras::ai_chat(&s, &h, text.as_deref(), img.as_deref())","extras::ai_chat(&s, &h, text.as_deref(), &imgs)")
rep("let mut text = None; let mut img = None;","let mut text = None; let mut img: Option<String> = None;")
a+='''
/// Which pages (0-based) the AI gets. mode 0 current page, 1 from-to range (1-based, blank "to" = last page), 2 whole document.
pub fn ai_page_list(mode: u8, from: &str, to: &str, cur: usize, n: usize) -> Vec<usize> {
    if n == 0 { return vec![]; }
    match mode {
        0 => vec![cur.min(n - 1)],
        2 => (0..n).collect(),
        _ => {
            let f = from.trim().parse::<usize>().unwrap_or(1).clamp(1, n);
            let t = if to.trim().is_empty() { n } else { to.trim().parse::<usize>().unwrap_or(n).clamp(1, n) };
            let (f, t) = if f <= t { (f, t) } else { (t, f) };
            (f - 1..t).collect()
        }
    }
}
'''
open('app.rs','w').write(a)
e=open('extras.rs').read()
e=e.replace("image_jpeg_b64: Option<&str>) -> Result<String, String> {","images: &[String]) -> Result<String, String> {",1)
e=e.replace('if i == last && *u { if let Some(img) = image_jpeg_b64 { parts.push(json!({"inline_data": {"mime_type": "image/jpeg", "data": img}})); } }','if i == last && *u { for img in images { parts.push(json!({"inline_data": {"mime_type": "image/jpeg", "data": img}})); } }',1)
e=e.replace('if i == last && *u && image_jpeg_b64.is_some() { msgs.push(json!({"role": "user", "content": [{"type": "text", "text": t}, {"type": "image_url", "image_url": {"url": format!("data:image/jpeg;base64,{}", image_jpeg_b64.unwrap())}}]})); }','if i == last && *u && !images.is_empty() { let mut c = vec![json!({"type": "text", "text": t})]; for im in images { c.push(json!({"type": "image_url", "image_url": {"url": format!("data:image/jpeg;base64,{}", im)}})); } msgs.push(json!({"role": "user", "content": c})); }',1)
open('extras.rs','w').write(e)
PYEOF
sed -i 's/(build b7)/(build b8)/; s/perf log (build b7)/perf log (build b8)/' app.rs
# standalone logic test
python3 - <<'PYEOF'
s=open('/tmp/scratch/app/src/app.rs').read()
i=s.index("pub fn ai_page_list")
open('/tmp/aitest.rs','w').write(s[i:]+'''
fn main(){
 assert_eq!(ai_page_list(0,"","",4,10),vec![4]);
 assert_eq!(ai_page_list(0,"","",99,10),vec![9]);
 assert_eq!(ai_page_list(2,"","",0,3),vec![0,1,2]);
 assert_eq!(ai_page_list(1,"2","4",0,10),vec![1,2,3]);
 assert_eq!(ai_page_list(1,"5","",0,8),vec![4,5,6,7]);
 assert_eq!(ai_page_list(1,"9","3",0,10),vec![2,3,4,5,6,7,8]);
 assert_eq!(ai_page_list(1,"1","500",0,339).len(),339);
 assert_eq!(ai_page_list(1,"x","y",0,3),vec![0,1,2]);
 assert_eq!(ai_page_list(1,"0","0",0,3),vec![0]);
 assert!(ai_page_list(1,"1","2",0,0).is_empty());
 println!("ok");}
''')
PYEOF
rustc -o /tmp/aitest /tmp/aitest.rs 2>&1 | head; /tmp/aitest
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E '^error' -A8 | head -30
