cd /tmp/scratch/shot; echo "11:15 selection implemented (app.rs: stext char hit-test, drag/dbl/triple, copy, Ctrl+A); static highlight verified in software render. Next: simulate pointer events in shot to verify interactions, then toolbar+tools." >> ~/NOTES_native.md
python3 - <<'EOF'
p='src/main.rs'; s=open(p).read()
s=s.replace("    let mut r = EguiSoftwareRender","""    if a.get(5).map(|s| s.as_str()) == Some("sim") {
        // simulate: layout frame, then drag / double / triple click, print selected text
        let run = |app: &mut App, evs: Vec<egui::Event>, t: f64| {
            let mut raw = egui::RawInput::default();
            raw.screen_rect = Some(egui::Rect::from_min_size(egui::pos2(0.0, 0.0), egui::vec2(w as f32, h as f32)));
            raw.time = Some(t);
            raw.events = evs;
            let _ = ctx.run(raw, |c| app.ui(c));
        };
        let pe = |p: egui::Pos2, pressed: bool| egui::Event::PointerButton { pos: p, button: egui::PointerButton::Primary, pressed, modifiers: egui::Modifiers::NONE };
        run(&mut app, vec![], 0.0);
        // drag across first line
        let (p0, p1) = (egui::pos2(300.0, 95.0), egui::pos2(520.0, 95.0));
        run(&mut app, vec![egui::Event::PointerMoved(p0)], 0.1);
        run(&mut app, vec![pe(p0, true)], 0.2);
        run(&mut app, vec![egui::Event::PointerMoved(egui::pos2(400.0, 95.0))], 0.3);
        run(&mut app, vec![egui::Event::PointerMoved(p1)], 0.4);
        run(&mut app, vec![pe(p1, false)], 0.5);
        println!("DRAG: {:?}", app.selected_text());
        // double click on 'SECRET' word
        let pw = egui::pos2(450.0, 95.0);
        let mut t = 1.0;
        for _ in 0..2 { run(&mut app, vec![egui::Event::PointerMoved(pw), pe(pw, true)], t); t += 0.05; run(&mut app, vec![pe(pw, false)], t); t += 0.05; }
        println!("DOUBLE: {:?}", app.selected_text());
        for _ in 0..3 { run(&mut app, vec![egui::Event::PointerMoved(pw), pe(pw, true)], t); t += 0.05; run(&mut app, vec![pe(pw, false)], t); t += 0.05; }
        println!("TRIPLE: {:?}", app.selected_text());
        return;
    }
    let mut r = EguiSoftwareRender""",1)
open(p,'w').write(s)
EOF
source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release 2>&1 | grep -E "^error|Finished" -A9 | head -30 | cut -c1-180); ./target/release/shot ../t.pdf ../x.ppm 1.0 0,0 sim
