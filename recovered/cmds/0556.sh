cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
s=s.replace("let widths = self.widths(); let maxw","let (p0, r0) = (self.tm.rec_prep, self.tm.rec_run); let widths = self.widths(); let maxw",1)
s=s.replace("        Ok(words)\n    }\n}","        self.tm.decode += tr.elapsed().as_secs_f32() * 1000.0 - (self.tm.rec_prep - p0) - (self.tm.rec_run - r0);\n        Ok(words)\n    }\n    pub fn take_timing(&mut self) -> Tm { std::mem::take(&mut self.tm) }\n}",1)
open('ocr.rs','w').write(s)
e=open('extras.rs').read()
def rep(a,b):
    global e
    assert a in e, a[:70]
    e=e.replace(a,b,1)
rep('crate::ocr::HOOK.set(|s| println!("S {s}")).ok();','crate::ocr::HOOK.set(|s| println!("S {s}")).ok();\n    crate::ocr::INFO.set(|s| println!("I {}", s.replace(\'\\n\', " "))).ok();\n    out(&format!("I {}", BUILD));')
rep("pub const RECYCLE","pub const RECYCLE") if False else None
e=e.replace("const RECYCLE_PAGES: usize = 40;","pub const BUILD: &str = \"LitePDF build 2026-10-04 fixed-shape GPU sessions (b3)\";\nconst RECYCLE_PAGES: usize = 40;",1)
# render timing + page timing + watchdog
rep("        let t = std::time::Instant::now();\n        let r = (|| -> Result<(Vec<u8>, usize, usize, f32), String> {","        let t = std::time::Instant::now(); eng.take_timing();\n        let r = (|| -> Result<(Vec<u8>, usize, usize, f32), String> {")
rep("        let mut res = eng.recognize(&rgb, w, h);","        let render_ms = t.elapsed().as_secs_f32() * 1000.0;\n        let mut res = eng.recognize(&rgb, w, h);\n        let page_secs = t.elapsed().as_secs_f32();\n        out(&format!(\"I page {} timing: render {render_ms:.0} ms, {}\", i + 1, eng.take_timing().line()));\n        if eng.provider.starts_with(\"DirectML\") { n_gpu += 1; if n_gpu >= 3 { gpu_secs += page_secs; } }\n        // watchdog: if the GPU stays slow, time the CPU on this same page and keep the faster engine\n        if eng.provider.starts_with(\"DirectML\") && n_gpu == 6 && !bench_done { bench_done = true; let avg = gpu_secs / 4.0;\n            if avg > 2.5 { out(&format!(\"I GPU pages 3-6 average {avg:.1} s, timing the CPU on the same page\"));\n                if let Ok(mut c) = crate::ocr::Engine::new(&dir, &dll, false) { let tb = std::time::Instant::now(); let r = c.recognize(&rgb, w, h); let cs = tb.elapsed().as_secs_f32();\n                    out(&format!(\"I CPU benchmark: {cs:.1} s for the same page ({})\", c.provider));\n                    if r.is_ok() && cs < avg * 0.8 { out(&format!(\"I CPU is faster ({cs:.1} s vs {avg:.1} s per page), switching to CPU for the rest\")); eng = c; res = r; } else { out(\"I keeping the GPU\"); } } } }")
rep("    let mut n = 0usize;\n    for &i in &pages {","    let mut n = 0usize; let mut n_gpu = 0usize; let mut gpu_secs = 0f32; let mut bench_done = false;\n    for &i in &pages {")
# parent: I tag, GPU name, build
rep('                "S" => { last_stage','                "I" => { ocr_log(&format!("  {rest}")); }\n                "S" => { last_stage')
rep('    ocr_log(&format!("--- OCR pages {}-{} of {} (force={force})", from + 1, to + 1, n));','    ocr_log(&format!("--- OCR pages {}-{} of {} (force={force}) - {}", from + 1, to + 1, n, BUILD));\n    ocr_log(&format!("  display adapters: {}  (DirectML uses adapter 0 by default); CPU threads: {}", gpu_names(), std::thread::available_parallelism().map(|n| n.get()).unwrap_or(0)));')
e+='''
/// Names of the display adapters (Windows registry), for ocr.log.
pub fn gpu_names() -> String {
    #[cfg(windows)]
    {
        let mut c = Command::new("reg"); nowin(&mut c);
        if let Ok(o) = c.args(["query", r"HKLM\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}", "/s", "/v", "DriverDesc"]).output() {
            let t = String::from_utf8_lossy(&o.stdout);
            let v: Vec<String> = t.lines().filter_map(|l| l.trim().strip_prefix("DriverDesc").map(|r| r.trim().trim_start_matches("REG_SZ").trim().to_string())).filter(|x| !x.is_empty()).collect();
            if !v.is_empty() { return v.join("; "); }
        }
        "unknown".into()
    }
    #[cfg(not(windows))]
    { "n/a".into() }
}
'''
open('extras.rs','w').write(e)
E
grep -n "last_title" app.rs | head -5; grep -n "fn main" -A3 main.rs | head; grep -n "with_title\|title" main.rs | head
