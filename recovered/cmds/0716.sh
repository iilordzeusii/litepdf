cd /tmp/scratch/app/src; python3 - <<'PYEOF'
u=open('bin/uitest.rs').read()
x='    // edit: ink on current page -> invalidate'
assert x in u
u=u.replace(x,'''    // stress: scroll + ctrl-wheel zoom in/out, then everything visible must become sharp
    for round in 0..6 {
        let ctrl = |dy: f32| vec![egui::Event::MouseWheel { unit: egui::MouseWheelUnit::Line, delta: egui::vec2(0.0, dy), modifiers: egui::Modifiers::CTRL, phase: egui::TouchPhase::Move }, egui::Event::PointerMoved(egui::pos2(600.0, 400.0))];
        pump(&ctx, &mut app, 12, |k| if k % 3 == 0 { ctrl(if round % 2 == 0 { 1.0 } else { -1.0 }) } else { wheel(-90.0) });
        pump(&ctx, &mut app, 8, |_| wheel(-200.0));
        let t = Instant::now(); let mut n = 0;
        loop { frame(&ctx, &mut app, vec![]); std::thread::sleep(Duration::from_millis(6)); n += 1; if app.miss_last == 0 || t.elapsed() > Duration::from_secs(8) { break; } }
        println!("stress round {round}: zoom {:.2} page {} -> missing visible tiles {} after {:.0} ms ({n} frames), watchdog resends {}", app.zoom, app.cur_page + 1, app.miss_last, t.elapsed().as_secs_f32() * 1000.0, app.watchdog);
    }
'''+x,1)
open('bin/uitest.rs','w').write(u)
PYEOF
source /tmp/scratch/wenv.sh; cd /tmp/scratch/app && timeout 118 cargo build --release --target x86_64-pc-windows-gnu --bin uitest 2>&1 | grep -E '^error' -A8 | head -30
