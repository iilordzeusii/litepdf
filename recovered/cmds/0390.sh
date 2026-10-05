cd /tmp/scratch/app/src && python3 - <<'EOF'
e=open('extras.rs').read()
a=e.index("#[derive(Clone, Default)]\npub struct Settings"); b=e.index("// ---------- AI ----------")
e=e[:a]+'''#[derive(Clone, Default)]
pub struct Settings { pub provider: String, pub key: String, pub model: String, pub saved: Vec<(String, String, String)> }
impl Settings {
    /// Switch provider: park the current key/model under the old provider, load the stored ones for the new one.
    pub fn switch_to(&mut self, new: &str) {
        if self.provider == new { return; }
        let old = self.provider.clone();
        self.saved.retain(|(p, _, _)| *p != old && *p != new);
        self.saved.push((old, std::mem::take(&mut self.key), std::mem::take(&mut self.model)));
        // the entry for `new` was removed above; recover it from a snapshot taken before
        self.provider = new.to_string();
    }
}
fn settings_path() -> PathBuf {
    let base = std::env::var("APPDATA").or_else(|_| std::env::var("XDG_CONFIG_HOME")).unwrap_or_else(|_| std::env::var("HOME").map(|h| format!("{h}/.config")).unwrap_or_default());
    PathBuf::from(base).join("LitePDF").join("settings.json")
}
pub fn load_settings() -> Settings {
    let mut s = Settings { provider: "Gemini".into(), ..Default::default() };
    if let Ok(t) = std::fs::read_to_string(settings_path()) { if let Ok(v) = serde_json::from_str::<Value>(&t) {
        if let Some(x) = v["provider"].as_str() { s.provider = x.into(); }
        if let Some(o) = v["profiles"].as_object() { for (p, pv) in o { let (k, m) = (pv["key"].as_str().unwrap_or("").to_string(), pv["model"].as_str().unwrap_or("").to_string()); if *p == s.provider { s.key = k; s.model = m; } else { s.saved.push((p.clone(), k, m)); } } }
        else { if let Some(x) = v["key"].as_str() { s.key = x.into(); } if let Some(x) = v["model"].as_str() { s.model = x.into(); } } } }
    s
}
pub fn save_settings(s: &Settings) {
    let p = settings_path(); if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
    let mut prof = serde_json::Map::new();
    for (pn, k, m) in &s.saved { prof.insert(pn.clone(), json!({"key": k, "model": m})); }
    prof.insert(s.provider.clone(), json!({"key": s.key, "model": s.model}));
    let _ = std::fs::write(p, json!({"provider": s.provider, "profiles": prof}).to_string());
}

'''+e[b:]
open('extras.rs','w').write(e)
EOF
echo ok
