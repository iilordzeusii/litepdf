cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
a=a.replace("    fn start_ocr(&mut self,","""    #[cfg(windows)]
    pub fn gpu_pref_probe(&mut self) {
        use std::os::windows::process::CommandExt;
        let exe = std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_default();
        let out = std::process::Command::new("reg").args(["query", "HKCU\\\\Software\\\\Microsoft\\\\DirectX\\\\UserGpuPreferences", "/v", &exe]).creation_flags(0x0800_0000).output();
        let s = match out { Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).lines().filter(|l| l.contains("GpuPreference")).collect::<Vec<_>>().join(" ").trim().to_string(), _ => "no per-app GPU preference set (Windows default)".into() };
        self.perf.header.push_str(&format!("\\nWindows GPU preference for this exe: {s}\\nworkers: {}", render::WORKERS));
    }
    fn start_ocr(&mut self,""",1)
open('app.rs','w').write(a)
PYEOF
grep -n 'tx.send\|Kind::\|Res::\|Src::Bytes\|try_recv\|rx\.' bin/rendcli.rs bin/uitest.rs | cut -c1-200
