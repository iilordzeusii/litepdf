cd /tmp/scratch/app/src && python3 - <<'EOF'
s=open('app.rs').read()
a=s.index('        egui::TopBottomPanel::top("bar").show(ctx, |ui| {'); b=s.index('        if self.show_find {')
new='''        if !self.styled {
            self.styled = true;
            let mut st = (*ctx.style()).clone();
            st.spacing.item_spacing = vec2(6.0, 6.0); st.spacing.button_padding = vec2(10.0, 5.0); st.spacing.interact_size.y = 28.0;
            let r = egui::CornerRadius::same(6);
            st.visuals.widgets.inactive.corner_radius = r; st.visuals.widgets.hovered.corner_radius = r; st.visuals.widgets.active.corner_radius = r; st.visuals.widgets.open.corner_radius = r;
            st.visuals.selection.bg_fill = Color32::from_rgb(45, 105, 220);
            st.visuals.widgets.inactive.weak_bg_fill = Color32::from_gray(52); st.visuals.widgets.hovered.weak_bg_fill = Color32::from_gray(70);
            st.visuals.panel_fill = Color32::from_gray(30);
            ctx.set_style(st);
        }
        egui::TopBottomPanel::top("bar").frame(egui::Frame::NONE.fill(Color32::from_gray(36)).inner_margin(egui::Margin::symmetric(8, 6)).stroke(Stroke::new(1.0, Color32::from_gray(20)))).show(ctx, |ui| {
            ui.horizontal(|ui| {
                self.menus(ui);
                ui.add_space(6.0); ui.separator(); ui.add_space(6.0);
                let tools = [(Tool::Select, "Select"), (Tool::Highlight, "Highlight"), (Tool::Underline, "Underline"), (Tool::Strike, "Strike"), (Tool::Ink, "Pen"), (Tool::Text, "Text"), (Tool::Eraser, "Eraser"), (Tool::Redact, "Redact"), (Tool::Sign, "Sign")];
                egui::Frame::NONE.fill(Color32::from_gray(26)).corner_radius(8.0).inner_margin(egui::Margin::symmetric(4, 2)).show(ui, |ui| { ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 2.0;
                    for (t, n) in tools {
                        let b = egui::Button::new(egui::RichText::new(n).size(13.5)).selected(self.tool == t).frame(self.tool == t).min_size(vec2(0.0, 26.0));
                        if ui.add(b).clicked() { self.commit_text(); self.tool = t; }
                    }
                }); });
                ui.add_space(6.0);
                let mut c = Color32::from_rgb((self.color[0] * 255.0) as u8, (self.color[1] * 255.0) as u8, (self.color[2] * 255.0) as u8);
                if ui.color_edit_button_srgba(&mut c).changed() { self.color = [c.r() as f32 / 255.0, c.g() as f32 / 255.0, c.b() as f32 / 255.0]; }
                if self.tool == Tool::Ink { ui.add(egui::Slider::new(&mut self.ink_width, 1.0..=12.0).text("width")); }
                if self.tool == Tool::Redact && ui.button("Apply redactions").clicked() {
                    if let Some(d) = self.doc.as_mut() { match ops::apply_all_redactions(d) { Ok(n) => self.status = format!("Applied {n} redaction(s)"), Err(e) => self.status = format!("Redact failed: {e}") } }
                    self.tex.clear(); self.thumbs.clear(); self.text.clear(); self.dirty = true;
                }
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if ui.button("Fit").on_hover_text("Fit page width").clicked() { if let Some(s) = self.sizes.get(self.cur_page) { self.zoom = ((self.view_w - 40.0) / s.x).clamp(0.1, 8.0); self.zoom_t = std::time::Instant::now(); } }
                    if ui.button("+").clicked() { self.zoom = (self.zoom * 1.25).min(8.0); self.zoom_t = std::time::Instant::now(); }
                    ui.label(format!("{:.0}%", self.zoom * 100.0));
                    if ui.button("\\u{2212}").clicked() { self.zoom = (self.zoom / 1.25).max(0.1); self.zoom_t = std::time::Instant::now(); }
                    ui.separator();
                    ui.toggle_value(&mut self.show_thumbs, "Pages");
                    if ui.button("Find").clicked() { self.show_find = !self.show_find; }
                });
            });
        });
'''
s=s[:a]+new+s[b:]
s=s.replace("    pub chat: Vec<(bool, String)>, pub chat_input: String,","    pub view_w: f32, pub chat: Vec<(bool, String)>, pub chat_input: String,",1)
s=s.replace("chat: vec![], chat_input: String::new(),","view_w: 900.0, chat: vec![], chat_input: String::new(),",1)
s=s.replace("            let area = ui.available_rect_before_wrap();","            let area = ui.available_rect_before_wrap(); self.view_w = area.width();",1)
open('app.rs','w').write(s)
EOF
cd /tmp/scratch/shot; sed -i 's/ocr_document(&mut d, &mut |i,n| eprintln!("page {i}\/{n}"))/ocr_document(\&mut d, 0, 0, \&mut |i,n,w| eprintln!("page {i}\/{n} {w}"))/' src/bin/e2e.rs; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 110 cargo build --release --bin shot 2>&1 | grep -E "^error" -A12 | head -90 | cut -c1-190
