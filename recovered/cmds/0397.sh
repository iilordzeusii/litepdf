cd /tmp/scratch/app/src && python3 - <<'EOF'
s=open('app.rs').read()
a=s.index("            ctx.set_cursor_icon(match self.tool {"); b=s.index("\n",a)
old=s[a:b]
new='''            let over_text = if matches!(self.tool, Tool::Select | Tool::Highlight | Tool::Underline | Tool::Strike) {
                match ui.input(|i| i.pointer.hover_pos()).filter(|p| area.contains(*p) && resp.hovered()).and_then(|p| to_pdf(&rects, p).filter(|(pg, _)| rects[*pg].contains(p)).map(|(pg, pp)| (pg, pp))) {
                    Some((pg, pp)) => self.page_chars(pg).iter().any(|c| c.c != '\\n' && c.r.expand(0.5).contains(pp)),
                    None => false }
            } else { false };
            if over_text || self.tool == Tool::Text { ctx.set_cursor_icon(egui::CursorIcon::Text); }
            else if matches!(self.tool, Tool::Ink | Tool::Redact | Tool::Sign) { ctx.set_cursor_icon(egui::CursorIcon::Crosshair); }
            else if self.tool == Tool::Eraser { ctx.set_cursor_icon(egui::CursorIcon::PointingHand); }'''
s=s[:a]+new+s[b:]
open('app.rs','w').write(s)
EOF
cd /tmp/scratch/shot; source ~/.cargo/env; export RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native; timeout 100 cargo build --release --bin shot 2>&1 | grep -E "^error" -A12 | head -40 | cut -c1-190
