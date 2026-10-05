cd /tmp/scratch/app/src && python3 - <<'EOF'
s=open('main.rs').read()
s=s.replace("use eframe::egui::{self,","use egui::{self,")
head,rest=s.split("impl eframe::App for App {",1)
upd,tail=rest.split("fn main()",1)
upd=upd.replace("fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) {","pub fn ui(&mut self, ctx: &egui::Context) {",1)
# upd ends with "    }\n}\n\n" ; make it an inherent impl
app="pub "+head.strip().replace("struct App {","struct App {",1)
app=app.replace("    doc: Option","    pub doc: Option").replace("    sizes","    pub sizes").replace("    tex:","    pub tex:").replace("    zoom","    pub zoom").replace("    scroll","    pub scroll").replace("    path","    pub path").replace("    fn open","    pub fn open")
app=app.replace("pub use","use")
app+="\nimpl App {\n"+upd.rstrip()+"\n"
open('app.rs','w').write(app+"\n")
open('main.rs','w').write('''mod app;
use app::App;
use eframe::egui;
use std::collections::HashMap;
impl eframe::App for Wrap { fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) { self.0.ui(ctx); } }
struct Wrap(App);
fn main'''+tail.replace("Box::new(app)","Box::new(Wrap(app))").replace("let mut app = App {","let mut app = App {",1))
EOF
sed -i 's/impl App {/impl App {/' app.rs; grep -n "^impl\|^pub struct\|^struct\|pub fn" app.rs | head; source ~/.cargo/env; source /tmp/scratch/wenv.sh; cd ..; timeout 80 cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E "^error|Finished" -A6 | head -20 | cut -c1-200
