cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
s=s.replace("""        let e = if !dll.exists()""","""        #[cfg(windows)]
        let pre: Option<String> = {
            use std::os::windows::ffi::OsStrExt;
            extern "system" { fn LoadLibraryW(p: *const u16) -> *mut core::ffi::c_void; fn GetLastError() -> u32; }
            let w: Vec<u16> = dll.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
            if dll.exists() && unsafe { LoadLibraryW(w.as_ptr()) }.is_null() { Some(format!("Windows could not load it (error {}). The Microsoft Visual C++ runtime or DirectML.dll may be missing", unsafe { GetLastError() })) } else { None }
        };
        #[cfg(not(windows))]
        let pre: Option<String> = None;
        let e = if pre.is_some() { pre } else if !dll.exists()""",1)
open('ocr.rs','w').write(s)
E
cat /tmp/scratch/litepdf.nsi
