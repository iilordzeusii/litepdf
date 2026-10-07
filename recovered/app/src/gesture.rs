//! Pure (platform independent) accumulator for Direct Manipulation content transforms.
//! Windows reports a cumulative transform (scale, x, y) since the gesture began; we turn it into
//! per-frame deltas, reset between gestures, and never let a viewport reset produce a jump.
#[derive(Clone, Copy, Debug)]
pub struct Gesture { pub dx: f32, pub dy: f32, pub zoom: f32, last_scale: f32, last_x: f32, last_y: f32, pinch: bool }
impl Default for Gesture { fn default() -> Self { Gesture::new() } }
impl Gesture {
    pub const fn new() -> Self { Gesture { dx: 0.0, dy: 0.0, zoom: 1.0, last_scale: 1.0, last_x: 0.0, last_y: 0.0, pinch: false } }
    /// OnContentUpdated with the content transform (xform[0], xform[4], xform[5]).
    pub fn content(&mut self, scale: f32, x: f32, y: f32) {
        if !scale.is_finite() || !x.is_finite() || !y.is_finite() || scale <= 0.0 { return; }
        if (scale - self.last_scale).abs() < 1e-6 && x == self.last_x && y == self.last_y { return; }
        if (scale - 1.0).abs() > 1e-6 { self.pinch = true; }
        if self.pinch { self.zoom *= scale / self.last_scale; } else { self.dx += x - self.last_x; self.dy += y - self.last_y; }
        self.last_scale = scale; self.last_x = x; self.last_y = y;
    }
    /// Viewport status became READY: returns true when the viewport must be reset to the origin (ZoomToRect).
    /// State is reset first so any update produced by the reset itself yields no delta.
    pub fn ready(&mut self) -> bool {
        let need = self.last_scale != 1.0 || self.last_x != 0.0 || self.last_y != 0.0;
        self.last_scale = 1.0; self.last_x = 0.0; self.last_y = 0.0; self.pinch = false; need
    }
    pub fn take(&mut self) -> (f32, f32, f32) { let r = (self.dx, self.dy, self.zoom); self.dx = 0.0; self.dy = 0.0; self.zoom = 1.0; r }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Rng(u64);
    impl Rng { fn n(&mut self) -> f32 { self.0 ^= self.0 << 13; self.0 ^= self.0 >> 7; self.0 ^= self.0 << 17; (self.0 % 100000) as f32 / 100000.0 } }
    #[test] fn pan_sums_to_final_offset() {
        let mut g = Gesture::new(); let mut tot = 0.0;
        for y in [1.0, 3.5, 3.5, 10.0, 22.25] { g.content(1.0, 0.0, y); tot += g.take().1; }
        assert!((tot - 22.25).abs() < 1e-4);
    }
    #[test] fn inertia_then_reset_has_no_jump() {
        let mut g = Gesture::new(); let mut tot = 0.0;
        for y in [5.0, 20.0, 60.0, 120.0, 150.0] { g.content(1.0, 0.0, y); tot += g.take().1; }
        assert!(g.ready()); // reset requested
        g.content(1.0, 0.0, 0.0); // transform after ZoomToRect: back at origin, must not scroll back
        assert_eq!(g.take(), (0.0, 0.0, 1.0)); assert!((tot - 150.0).abs() < 1e-4);
        assert!(!g.ready()); // second READY (viewport reset) requests nothing
    }
    #[test] fn new_gesture_starts_from_zero() {
        let mut g = Gesture::new();
        g.content(1.0, 0.0, 40.0); g.take(); g.ready(); g.content(1.0, 0.0, 0.0); g.take();
        g.content(1.0, 0.0, 7.0); assert!((g.take().1 - 7.0).abs() < 1e-5);
    }
    #[test] fn pinch_is_product_of_ratios_and_continuous() {
        let mut g = Gesture::new(); let mut z = 1.0f32; let mut s = 1.0f32;
        for k in 1..=200 { s = 1.0 + k as f32 * 0.01; g.content(s, 3.0, 3.0); let r = g.take().2; assert!(r > 1.0 && r < 1.02, "step {r}"); z *= r; }
        assert!((z - s).abs() / s < 1e-4);
        // pinch in
        let mut s2 = s; for _ in 0..100 { s2 *= 0.99; g.content(s2, 0.0, 0.0); z *= g.take().2; }
        assert!((z - s2).abs() / s2 < 1e-3);
    }
    #[test] fn pan_noise_during_pinch_ignored() {
        let mut g = Gesture::new(); g.content(1.2, 50.0, 50.0); let (dx, dy, z) = g.take();
        assert_eq!((dx, dy), (0.0, 0.0)); assert!((z - 1.2).abs() < 1e-5);
    }
    #[test] fn garbage_ignored() {
        let mut g = Gesture::new(); g.content(0.0, 1.0, 1.0); g.content(f32::NAN, 1.0, 1.0); g.content(1.0, f32::INFINITY, 0.0);
        assert_eq!(g.take(), (0.0, 0.0, 1.0));
    }
    #[test] fn stress_random_gestures_conserve_total() {
        let mut r = Rng(0x9E3779B97F4A7C15);
        let mut g = Gesture::new();
        for _ in 0..20000 {
            let n = 1 + (r.n() * 60.0) as usize; let mut y = 0.0f32; let mut tot = 0.0f32;
            for _ in 0..n { y += (r.n() - 0.3) * 40.0; g.content(1.0, 0.0, y); tot += g.take().1; }
            assert!((tot - y).abs() < 1e-2 * (1.0 + y.abs()), "{tot} vs {y}");
            if g.ready() { g.content(1.0, 0.0, 0.0); let t = g.take(); assert_eq!(t, (0.0, 0.0, 1.0)); }
            assert!(!g.ready());
        }
    }
    #[test] fn stress_random_pinch_conserve_total() {
        let mut r = Rng(12345);
        let mut g = Gesture::new();
        for _ in 0..20000 {
            let mut z = 1.0f32; let mut s = 1.0f32; let n = 1 + (r.n() * 80.0) as usize;
            for _ in 0..n { s = (s * (0.97 + r.n() * 0.06)).clamp(0.2, 5.0); g.content(s, r.n() * 9.0, r.n() * 9.0); z *= g.take().2; }
            if (s - 1.0).abs() > 1e-6 { assert!((z - s).abs() / s < 2e-3, "{z} vs {s}"); }
            if g.ready() { g.content(1.0, 0.0, 0.0); g.take(); }
        }
    }
}
