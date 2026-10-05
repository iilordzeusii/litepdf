cd /tmp/scratch/app/src && python3 - <<'EOF'
s=open('app.rs').read()
old="                        if resp.triple_clicked()"
new="""                        let mut hit_form = false;
                        if resp.clicked() && tool == Tool::Select { if let Some(d) = self.doc.as_ref() {
                            let fl = ops::fields(d, pg as i32);
                            if let Some(f) = fl.into_iter().find(|f| !f.readonly && pp.x >= f.rect.x0 && pp.x <= f.rect.x1 && pp.y >= f.rect.y0 && pp.y <= f.rect.y1) {
                                use mupdf::pdf::WidgetType as W;
                                match f.kind {
                                    W::Text | W::Combobox => { self.form_edit = Some((pg, f.clone(), f.value.clone())); hit_form = true; }
                                    W::Checkbox | W::RadioButton => { let r = ops::toggle_field(self.doc.as_mut().unwrap(), pg as i32, &f); if r.unwrap_or(false) { self.invalidate(pg); } hit_form = true; }
                                    _ => {}
                                }
                            } } }
                        if hit_form {}
                        else if resp.triple_clicked()"""
assert old in s
s=s.replace(old,new,1)
# overlay
old2="            // on-page text box\n"
new2="""            if let Some((pg, f, val)) = &mut self.form_edit {
                let r = rects[*pg];
                let rr = Rect::from_min_max(r.min + vec2(f.rect.x0, f.rect.y0) * z, r.min + vec2(f.rect.x1, f.rect.y1) * z);
                let mut done = false;
                egui::Area::new(egui::Id::new("fform")).fixed_pos(rr.min).order(egui::Order::Foreground).show(ctx, |ui| {
                    let te = egui::TextEdit::singleline(val).desired_width(rr.width()).font(FontId::proportional((rr.height() * 0.65).max(10.0)));
                    let resp = ui.add(te); resp.request_focus();
                    if resp.lost_focus() { done = true; }
                });
                if done { let (pg, f, v) = self.form_edit.take().unwrap(); if v != f.value { if let Some(d) = self.doc.as_mut() { let _ = ops::set_field(d, pg as i32, f.xref, &v); } self.invalidate(pg); } }
            }
            // on-page text box
"""
s=s.replace(old2,new2,1)
open('app.rs','w').write(s)
EOF
cd /tmp/scratch/shot; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 110 cargo build --release --bin shot 2>&1 | grep -E "^error|Finished" -A9 | head -40 | cut -c1-170
