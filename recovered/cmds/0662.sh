cd /tmp/scratch/app/src; python3 - <<'PYEOF'
a=open('app.rs').read()
i=a.index("pub struct Perf {"); j=a.index("const TEX_BUDGET")
perf='''#[derive(Clone, Copy)]
pub struct Diag { pub raw_wheel: bool, pub sync_mode: bool, pub snap: bool, pub upload1: bool }
impl Default for Diag { fn default() -> Self { Diag { raw_wheel: true, sync_mode: false, snap: true, upload1: true } } }
pub struct Swipe { pub t0: std::time::Instant, pub last: std::time::Instant, pub req: f32, pub applied: f32, pub series: Vec<(f32, f32)> }

pub struct Perf {
    pub active: bool, any_active: bool, prev_active: bool, last_start: Option<std::time::Instant>, sec: std::time::Instant, t_run: std::time::Instant,
    frames: u32, sum_ms: f32, max_ms: f32, gaps: Vec<f32>, ups: u32, up_sum: f32, up_max: f32, rend: u32, r_sum: f32, r_max: f32, pub sync: u32, pub sync_frame: u32, sync_max: f32, refresh_ms: f32, lines: u32, started: bool,
    marks: Vec<(&'static str, f32)>, t_begin: std::time::Instant, pending: String, pub white: u32, pub baseonly: u32, pub sharp: u32, f_white: bool, f_base: bool, f_any: bool,
    pub hits: u32, pub misses: u32, pub wlines: u32, pub header: String, slow: u32, pub dropped_up: u32,
}
impl Perf {
    pub fn new() -> Self { let n = std::time::Instant::now(); Perf { active: false, any_active: false, prev_active: false, last_start: None, sec: n, t_run: n, frames: 0, sum_ms: 0.0, max_ms: 0.0, gaps: vec![], ups: 0, up_sum: 0.0, up_max: 0.0, rend: 0, r_sum: 0.0, r_max: 0.0, sync: 0, sync_frame: 0, sync_max: 0.0, refresh_ms: 0.0, lines: 0, started: false,
        marks: vec![], t_begin: n, pending: String::new(), white: 0, baseonly: 0, sharp: 0, f_white: false, f_base: false, f_any: false, hits: 0, misses: 0, wlines: 0, header: String::new(), slow: 0, dropped_up: 0 } }
    pub fn upload(&mut self, ms: f32) { self.ups += 1; self.up_sum += ms; self.up_max = self.up_max.max(ms); }
    pub fn rendered(&mut self, ms: f32) { self.rend += 1; self.r_sum += ms; self.r_max = self.r_max.max(ms); }
    pub fn synced(&mut self, ms: f32) { self.sync += 1; self.sync_frame += 1; self.sync_max = self.sync_max.max(ms); }
    pub fn refreshed(&mut self, ms: f32) { self.refresh_ms = self.refresh_ms.max(ms); }
    pub fn begin(&mut self) { self.t_begin = std::time::Instant::now(); self.marks.clear(); }
    pub fn mark(&mut self, name: &'static str) { let t = self.t_begin.elapsed().as_secs_f32() * 1000.0; self.marks.push((name, t)); }
    pub fn note(&mut self, s: String) { if self.pending.len() < 200_000 { self.pending.push_str(&format!("t={:>4}s  {}\\n", self.t_run.elapsed().as_secs(), s)); } }
    pub fn vis(&mut self, state: u8) { self.f_any = true; match state { 0 => self.f_white = true, 1 => self.f_base = true, _ => {} } }
    pub fn worker_job(&mut self, wid: usize, kind: &str, page: usize, total: f32, list: f32, hit: bool) {
        self.rendered(total); if hit { self.hits += 1 } else { self.misses += 1 }
        if total > 150.0 && self.wlines < 400 { self.wlines += 1; self.note(format!("worker{wid} slow job: {kind} page {page} took {total:.0} ms (display list {list:.0} ms, draw {:.0} ms, list cache {})", total - list, if hit { "hit" } else { "miss" })); }
    }
    pub fn frame(&mut self, t0: std::time::Instant, bytes: usize, tiles: usize, queue: usize) {
        self.sync_frame = 0;
        let ms = t0.elapsed().as_secs_f32() * 1000.0;
        if let Some(l) = self.last_start { let gap = t0.duration_since(l).as_secs_f32() * 1000.0; if self.prev_active && self.active && gap < 2000.0 { self.gaps.push(gap); } }
        self.last_start = Some(t0); self.prev_active = self.active;
        self.frames += 1; self.sum_ms += ms; self.max_ms = self.max_ms.max(ms);
        if self.f_any && self.active { if self.f_white { self.white += 1; } else if self.f_base { self.baseonly += 1; } else { self.sharp += 1; } }
        self.f_white = false; self.f_base = false; self.f_any = false;
        if ms > 30.0 && self.slow < 300 {
            self.slow += 1;
            let mut prev = 0.0; let mut s = String::new();
            for (n, t) in &self.marks { s.push_str(&format!(" {n}={:.1}", t - prev)); prev = *t; }
            s.push_str(&format!(" rest={:.1}", ms - prev));
            self.note(format!("SLOW frame {ms:.1} ms (ms per stage:{s}; sync tile renders this second={})", self.sync));
        }
        if self.active { self.any_active = true; }
        self.active = false;
        if self.sec.elapsed().as_secs_f32() >= 1.0 {
            use std::io::Write;
            let busy = (self.any_active || self.sync > 0 || self.refresh_ms > 0.0) && self.lines < 20000;
            if busy || !self.pending.is_empty() {
                let p = extras::settings_path().with_file_name("perf.log");
                if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
                let f = if !self.started { self.started = true; std::fs::OpenOptions::new().create(true).write(true).truncate(true).open(&p) } else { std::fs::OpenOptions::new().create(true).append(true).open(&p) };
                if let Ok(mut f) = f {
                    if self.lines == 0 { let _ = writeln!(f, "LitePDF perf log (build b5). One line per second while scrolling/zooming. frame = time inside our UI update. gap = time between frame starts (p50/p95/p99/max, nothing filtered). up = texture uploads. render = worker jobs. vis = frames whose visible pages were white / low-res base only / sharp. lc = display-list cache hits/misses.\\n{}", self.header); }
                    if busy {
                        let mut g = std::mem::take(&mut self.gaps); g.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                        let q = |f: f32| -> f32 { if g.is_empty() { 0.0 } else { g[((g.len() as f32 - 1.0) * f).round() as usize] } };
                        let _ = writeln!(f, "t={:>4}s frames={:<3} frame_avg={:.1}ms frame_max={:.1}ms gap p50={:.1} p95={:.1} p99={:.1} max={:.1}ms up={}x(max {:.1}ms) render={}x(avg {:.0}ms max {:.0}ms) sync={}x(max {:.0}ms) refresh_max={:.0}ms queue={} tex={} mem={}MB vis(white/base/sharp)={}/{}/{} lc={}/{}",
                            self.t_run.elapsed().as_secs(), self.frames, self.sum_ms / self.frames.max(1) as f32, self.max_ms, q(0.5), q(0.95), q(0.99), g.last().cloned().unwrap_or(0.0), self.ups, self.up_max, self.rend, self.r_sum / self.rend.max(1) as f32, self.r_max, self.sync, self.sync_max, self.refresh_ms, queue, tiles, bytes >> 20, self.white, self.baseonly, self.sharp, self.hits, self.misses);
                        self.lines += 1;
                    }
                    if !self.pending.is_empty() { let _ = f.write_all(std::mem::take(&mut self.pending).as_bytes()); }
                }
            }
            self.gaps.clear();
            self.sec = std::time::Instant::now(); self.frames = 0; self.sum_ms = 0.0; self.max_ms = 0.0; self.ups = 0; self.up_sum = 0.0; self.up_max = 0.0; self.rend = 0; self.r_sum = 0.0; self.r_max = 0.0; self.sync = 0; self.sync_max = 0.0; self.refresh_ms = 0.0; self.any_active = false; self.white = 0; self.baseonly = 0; self.sharp = 0; self.hits = 0; self.misses = 0;
        }
    }
}

'''
a=a[:i]+perf+a[j:]
open('app.rs','w').write(a)
PYEOF
grep -n 'UPLOAD_BUDGET\|sync_max\b' app.rs | head -4; grep -n 'menu_button\|"File"\|"Help"' app.rs | head
