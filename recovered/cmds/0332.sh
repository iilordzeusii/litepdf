cd /tmp/scratch/app/src && python3 - <<'EOF'
s=open('app.rs').read()
s=s.replace("use crate::ops;","use crate::{ops, extras};\nuse std::sync::mpsc::{channel, Receiver, Sender};")
s=s.replace("pub struct TextEditState","""pub enum Msg { Status(String), Reload(String), Ai(Result<String, String>) }
#[derive(PartialEq, Clone, Copy)]
pub enum Dlg { None, Split, Compress, Protect, Sign, Password, Merge }
pub struct TextEditState""",1)
s=s.replace("    pub want_scroll_to: Option<f32>,\n}","""    pub want_scroll_to: Option<f32>,
    pub settings: extras::Settings,
    pub show_ai: bool, pub ai_prompt: String, pub ai_out: String, pub ai_busy: bool,
    pub ai_use_text: bool, pub ai_use_image: bool, pub ai_scope_doc: bool,
    pub tx: Sender<Msg>, pub rx: Receiver<Msg>,
    pub dlg: Dlg, pub f1: String, pub f2: String, pub f3: String, pub quality: f32, pub perm_print: bool, pub perm_copy: bool, pub perm_edit: bool,
    pub pending: Option<PdfDocument>, pub pending_path: String,
    pub form_edit: Option<(usize, ops::Field, String)>,
    pub cur_page: usize,
    pub busy: String,
}""")
s=s.replace("show_find: false, find_q: String::new(),","settings: extras::load_settings(), show_ai: false, ai_prompt: String::new(), ai_out: String::new(), ai_busy: false, ai_use_text: true, ai_use_image: false, ai_scope_doc: false, tx, rx, dlg: Dlg::None, f1: String::new(), f2: String::new(), f3: String::new(), quality: 70.0, perm_print: true, perm_copy: true, perm_edit: false, pending: None, pending_path: String::new(), form_edit: None, cur_page: 0, busy: String::new(),\n            show_find: false, find_q: String::new(),")
s=s.replace("    pub fn new() -> Self {\n","    pub fn new() -> Self {\n        let (tx, rx) = channel();\n",1)
# open with password
s=s.replace("""            Ok(d) => { self.set_doc(d); self.path = p.to_string(); self.dirty = false; self.status = format!("Opened {p}"); }""","""            Ok(d) => {
                if d.needs_password().unwrap_or(false) { self.pending = Some(d); self.pending_path = p.to_string(); self.f1.clear(); self.dlg = Dlg::Password; return; }
                self.set_doc(d); self.path = p.to_string(); self.dirty = false; self.status = format!("Opened {p}"); }""")
open('app.rs','w').write(s)
EOF
grep -n "fn save_to" app.rs
