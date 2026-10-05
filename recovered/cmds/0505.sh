cd /tmp/scratch/app/src; cat > crash.rs <<'EOF'
//! Crash log: panics and Windows exceptions are written to %APPDATA%\LitePDF\crash.log before the process dies.
use std::io::Write;
fn path() -> std::path::PathBuf { crate::extras::settings_path().with_file_name("crash.log") }
fn write(msg: &str) {
    let p = path(); if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
        let st = crate::ocr::STAGE.lock().map(|s| s.clone()).unwrap_or_default();
        let (ws, peak) = crate::extras::mem_mb();
        let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let _ = writeln!(f, "---- crash (unix time {t}, pid {}, litepdf {}) ----\nlast OCR stage: {st}\nmemory: working set {ws} MB, peak {peak} MB\n{msg}", std::process::id(), env!("CARGO_PKG_VERSION"));
    }
}
pub fn install() {
    std::panic::set_hook(Box::new(|info| {
        let bt = std::backtrace::Backtrace::force_capture();
        write(&format!("panic: {info}\n{bt}"));
    }));
    #[cfg(windows)]
    unsafe {
        use std::ffi::c_void;
        extern "system" {
            fn SetUnhandledExceptionFilter(f: Option<unsafe extern "system" fn(*const c_void) -> i32>) -> *const c_void;
            fn GetModuleHandleExW(flags: u32, addr: *const c_void, out: *mut *mut c_void) -> i32;
            fn GetModuleFileNameW(m: *mut c_void, buf: *mut u16, n: u32) -> u32;
        }
        unsafe extern "system" fn filter(p: *const c_void) -> i32 {
            // EXCEPTION_POINTERS { *EXCEPTION_RECORD, *CONTEXT }; EXCEPTION_RECORD { u32 code, u32 flags, *record, *address, ... }
            let rec = *(p as *const *const u8);
            let code = *(rec as *const u32); let addr = *(rec.add(16) as *const *const c_void);
            let mut m: *mut c_void = std::ptr::null_mut();
            let mut name = String::from("unknown");
            if GetModuleHandleExW(0x4 | 0x2, addr, &mut m) != 0 {
                let mut buf = [0u16; 520]; let n = GetModuleFileNameW(m, buf.as_mut_ptr(), 520) as usize;
                name = String::from_utf16_lossy(&buf[..n.min(520)]);
            }
            write(&format!("windows exception 0x{code:08X} at {addr:?} in module {name}"));
            1 // EXCEPTION_EXECUTE_HANDLER
        }
        SetUnhandledExceptionFilter(Some(filter));
    }
}
EOF
python3 - <<'E'
m=open('main.rs').read()
m=m.replace("mod ocr;","mod ocr;\nmod crash;")
m=m.replace("    let path = std::env::args().nth(1).unwrap_or_default();","""    crash::install();
    let argv: Vec<String> = std::env::args().collect();
    if argv.get(1).map(|s| s == "--ocr").unwrap_or(false) { std::process::exit(extras::ocr_child_main(&argv[2..])); }
    if argv.get(1).map(|s| s == "--crashtest").unwrap_or(false) { unsafe { std::ptr::write_volatile(std::ptr::null_mut::<u32>(), 1); } }
    let path = std::env::args().nth(1).unwrap_or_default();""",1)
open('main.rs','w').write(m)
o=open('ops.rs').read()
o=o.replace("pub fn merge(","/// Faster save for large documents: compress streams, no garbage collection or cleaning.\npub fn save_fast(doc: &PdfDocument, out: &str) -> Result<(), Error> {\n    let mut o = PdfWriteOptions::default(); o.set_compress(true);\n    doc.save_with_options(out, o)\n}\n\npub fn merge(",1)
open('ops.rs','w').write(o)
a=open('app.rs').read()
a=a.replace("extras::ocr_document(&mut d, from, to, force, &mut |m| { let _ = tx2.send(Msg::Note(m)); })?;","extras::ocr_document(&snap, &mut d, from, to, force, &mut |m| { let _ = tx2.send(Msg::Note(m)); })?;")
a=a.replace("if n.words > 0 { ops::save(&d, &out, true).map_err(|e| e.to_string())?; }","if n.words > 0 { extras::ocr_log(\"saving result\"); ops::save_fast(&d, &out).map_err(|e| e.to_string())?; extras::ocr_log(\"result saved, reloading\"); }")
a=a.replace("        std::thread::spawn(move || {\n            let r = (|| -> Result<extras::OcrStats","        let _ = std::thread::Builder::new().stack_size(64 << 20).spawn(move || {\n            let r = (|| -> Result<extras::OcrStats")
a=a.replace("if n.empty > 0 { format!(\", {} had no readable text\", n.empty) } else { String::new() }, n.engine)","if n.empty > 0 { format!(\", {} had no readable text\", n.empty) } else { String::new() }, n.engine).replace(\". Engine\", &format!(\"{}. Engine\", if n.failed > 0 { format!(\", {} page(s) failed (see ocr.log)\", n.failed) } else { String::new() }))")
open('app.rs','w').write(a)
c=open('bin/ocrcli.rs').read()
c=c.replace("#[path = \"../ocr.rs\"] mod ocr;","#[path = \"../ocr.rs\"] mod ocr;\n#[path = \"../crash.rs\"] mod crash;")
c=c.replace("    let a: Vec<String> = std::env::args().collect();","    crash::install();\n    let a: Vec<String> = std::env::args().collect();\n    if a.get(1).map(|s| s == \"--ocr\").unwrap_or(false) { std::process::exit(extras::ocr_child_main(&a[2..])); }")
c=c.replace("extras::ocr_document(&mut d, 0, n - 1,","extras::ocr_document(&a[1], &mut d, 0, n - 1,")
open('bin/ocrcli.rs','w').write(c)
E
grep -n "std::thread::Builder\|ocr_document" app.rs | head; cd ..; source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E "^error" -A9 | head -60
