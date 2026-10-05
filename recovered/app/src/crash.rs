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
