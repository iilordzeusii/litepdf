cd /tmp/scratch/app/src; python3 - <<'E'
a=open('app.rs').read()
a=a.replace("pub doc: Option<PdfDocument>,","pub doc: Option<PdfDocument>,\n    pub links: HashMap<usize, Vec<(mupdf::Rect, LinkT)>>,",1)
a=a.replace("App { doc: None,","App { doc: None, links: HashMap::new(),",1)
a=a.replace("self.text.clear();","self.text.clear(); self.links.clear();")
a=a.replace("self.text.remove(&page);","self.text.remove(&page); self.links.remove(&page);")
a=a.replace("    pub fn page_chars(&mut self","""    pub fn page_links(&mut self, i: usize) -> &Vec<(mupdf::Rect, LinkT)> {
        if !self.links.contains_key(&i) {
            let mut out = vec![];
            if let Some(doc) = &self.doc {
                if let Ok(pg) = doc.load_page(i as i32) {
                    if let Ok(it) = pg.links() {
                        for l in it {
                            let d = l.dest.or_else(|| doc.resolve_link(&l.uri).ok().flatten());
                            if let Some(d) = d {
                                use mupdf::DestinationKind as K;
                                let y = match d.kind { K::FitH { top } | K::FitBH { top } => top, K::XYZ { top, .. } => top, K::FitR { top, .. } => Some(top), _ => None };
                                out.push((l.bounds, LinkT::Page(d.loc.page_number as usize, y)));
                            } else if !l.uri.is_empty() { out.push((l.bounds, LinkT::Uri(l.uri.clone()))); }
                        }
                    }
                }
            }
            self.links.insert(i, out);
        }
        &self.links[&i]
    }
    pub fn page_chars(&mut self""",1)
a=a.replace("pub struct App","#[derive(Clone, Debug)]\npub enum LinkT { Page(usize, Option<f32>), Uri(String) }\n\npub struct App",1)
# hover + click
a=a.replace("            if over_text || self.tool == Tool::Text {","""            let over_link = if self.tool == Tool::Select {
                match ui.input(|i| i.pointer.hover_pos()).filter(|p| area.contains(*p) && resp.hovered()).and_then(|p| to_pdf(&rects, p).filter(|(pg, _)| rects[*pg].contains(p))) {
                    Some((pg, pp)) => self.page_links(pg).iter().any(|(r, _)| pp.x >= r.x0 && pp.x <= r.x1 && pp.y >= r.y0 && pp.y <= r.y1),
                    None => false }
            } else { false };
            if over_link { ctx.set_cursor_icon(egui::CursorIcon::PointingHand); }
            else if over_text || self.tool == Tool::Text {""",1)
a=a.replace("                        let mut hit_form = false;\n","""                        let mut hit_form = false;
                        if resp.clicked() && tool == Tool::Select {
                            let hit = self.page_links(pg).iter().find(|(r, _)| pp.x >= r.x0 && pp.x <= r.x1 && pp.y >= r.y0 && pp.y <= r.y1).map(|x| x.1.clone());
                            match hit {
                                Some(LinkT::Page(p, y)) => { let p = p.min(self.sizes.len().saturating_sub(1)); let off = self.offsets(); self.want_scroll_to = Some(off[p] + y.unwrap_or(0.0) * self.zoom - 12.0); self.cur_page = p; self.sel = None; hit_form = true; }
                                Some(LinkT::Uri(u)) => { extras::open_url(&u); self.status = format!("Opening {u}"); hit_form = true; }
                                None => {}
                            }
                        }
""",1)
a=a.replace("if resp.clicked() && tool == Tool::Select { if let Some(d) = self.doc.as_ref() {","if resp.clicked() && tool == Tool::Select && !hit_form { if let Some(d) = self.doc.as_ref() {",1)
open('app.rs','w').write(a)
e=open('extras.rs').read()
e+='''
/// Open a web or mail link in the default handler. Only http, https and mailto are allowed.
pub fn open_url(u: &str) {
    let l = u.to_ascii_lowercase();
    if !(l.starts_with("http://") || l.starts_with("https://") || l.starts_with("mailto:")) { return; }
    #[cfg(windows)]
    { let mut c = Command::new("rundll32.exe"); nowin(&mut c); let _ = c.arg("url.dll,FileProtocolHandler").arg(u).spawn(); }
    #[cfg(not(windows))]
    { let _ = Command::new("xdg-open").arg(u).spawn(); }
}
'''
open('extras.rs','w').write(e)
E
cd ..; source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E "^error" -A12 | head -60
