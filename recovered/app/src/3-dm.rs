//! Native Windows precision-touchpad input via Direct Manipulation (same method Chromium uses).
//! Windows turns touchpad contacts into continuous pan / pinch with OS inertia and press-to-stop;
//! we only read the resulting transform deltas. Falls back silently to the plain wheel path if init fails.
#[cfg(windows)]
mod imp {
    use std::cell::RefCell;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Mutex, OnceLock};
    use windows::core::{implement, Ref, BOOL};
    use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, RECT, WPARAM};
    use windows::Win32::Graphics::DirectManipulation::*;
    use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER};
    use windows::Win32::UI::Input::Pointer::GetPointerType;
    use windows::Win32::UI::Shell::{DefSubclassProc, SetWindowSubclass};
    use windows::Win32::UI::WindowsAndMessaging::{DM_POINTERHITTEST, PT_TOUCHPAD, POINTER_INPUT_TYPE};

    use crate::gesture::Gesture;
    static ACC: Mutex<Gesture> = Mutex::new(Gesture::new());
    static ACTIVE: AtomicBool = AtomicBool::new(false);
    static OK: AtomicBool = AtomicBool::new(false);
    static CTX: OnceLock<egui::Context> = OnceLock::new();
    static DPR: Mutex<f32> = Mutex::new(1.0);

    struct Dm { _manager: IDirectManipulationManager, update: IDirectManipulationUpdateManager, viewport: IDirectManipulationViewport }
    thread_local! { static DM: RefCell<Option<Dm>> = const { RefCell::new(None) }; }

    #[implement(IDirectManipulationViewportEventHandler, IDirectManipulationInteractionEventHandler)]
    struct Handler;

    impl IDirectManipulationViewportEventHandler_Impl for Handler_Impl {
        fn OnViewportStatusChanged(&self, viewport: Ref<IDirectManipulationViewport>, current: DIRECTMANIPULATION_STATUS, previous: DIRECTMANIPULATION_STATUS) -> windows::core::Result<()> {
            if current == previous { return Ok(()); }
            if current == DIRECTMANIPULATION_READY {
                let need = ACC.lock().unwrap().ready();
                if need { if let Some(v) = viewport.as_ref() { unsafe { let _ = v.ZoomToRect(0.0, 0.0, 1000.0, 1000.0, false); } } }
            }
            Ok(())
        }
        fn OnViewportUpdated(&self, _viewport: Ref<IDirectManipulationViewport>) -> windows::core::Result<()> { Ok(()) }
        fn OnContentUpdated(&self, _viewport: Ref<IDirectManipulationViewport>, content: Ref<IDirectManipulationContent>) -> windows::core::Result<()> {
            let Some(c) = content.as_ref() else { return Ok(()); };
            let mut m = [0f32; 6];
            unsafe { c.GetContentTransform(&mut m)?; }
            ACC.lock().unwrap().content(m[0], m[4], m[5]);
            Ok(())
        }
    }
    impl IDirectManipulationInteractionEventHandler_Impl for Handler_Impl {
        fn OnInteraction(&self, _viewport: Ref<IDirectManipulationViewport2>, interaction: DIRECTMANIPULATION_INTERACTION_TYPE) -> windows::core::Result<()> {
            if interaction == DIRECTMANIPULATION_INTERACTION_BEGIN { ACTIVE.store(true, Ordering::SeqCst); }
            else if interaction == DIRECTMANIPULATION_INTERACTION_END { ACTIVE.store(false, Ordering::SeqCst); }
            if let Some(c) = CTX.get() { c.request_repaint(); }
            Ok(())
        }
    }

    unsafe extern "system" fn subclass(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM, _id: usize, _data: usize) -> LRESULT {
        if msg == DM_POINTERHITTEST {
            let id = (wp.0 & 0xFFFF) as u32;
            let mut t = POINTER_INPUT_TYPE(0);
            let ok = unsafe { GetPointerType(id, &mut t) }.is_ok();
            if ok && t == PT_TOUCHPAD {
                DM.with(|d| { if let Some(dm) = d.borrow().as_ref() { unsafe { let _ = dm.viewport.SetContact(id); } } });
                return LRESULT(0);
            }
        }
        unsafe { DefSubclassProc(hwnd, msg, wp, lp) }
    }

    pub fn init(hwnd: isize, ctx: &egui::Context) -> Result<(), String> {
        unsafe {
            let hwnd = HWND(hwnd as *mut core::ffi::c_void);
            let manager: IDirectManipulationManager = CoCreateInstance(&DirectManipulationManager, None, CLSCTX_INPROC_SERVER).map_err(|e| format!("manager {e}"))?;
            let update: IDirectManipulationUpdateManager = manager.GetUpdateManager().map_err(|e| format!("update mgr {e}"))?;
            let viewport: IDirectManipulationViewport = manager.CreateViewport(None::<&IDirectManipulationFrameInfoProvider>, hwnd).map_err(|e| format!("viewport {e}"))?;
            let cfg = DIRECTMANIPULATION_CONFIGURATION_INTERACTION | DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_X | DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_Y | DIRECTMANIPULATION_CONFIGURATION_TRANSLATION_INERTIA | DIRECTMANIPULATION_CONFIGURATION_RAILS_X | DIRECTMANIPULATION_CONFIGURATION_RAILS_Y | DIRECTMANIPULATION_CONFIGURATION_SCALING;
            viewport.ActivateConfiguration(cfg).map_err(|e| format!("cfg {e}"))?;
            viewport.SetViewportOptions(DIRECTMANIPULATION_VIEWPORT_OPTIONS_MANUALUPDATE).map_err(|e| format!("opts {e}"))?;
            let r = RECT { left: 0, top: 0, right: 1000, bottom: 1000 };
            viewport.SetViewportRect(&r).map_err(|e| format!("rect {e}"))?;
            manager.Activate(hwnd).map_err(|e| format!("activate {e}"))?;
            viewport.Enable().map_err(|e| format!("enable {e}"))?;
            let h: IDirectManipulationViewportEventHandler = Handler.into();
            viewport.AddEventHandler(Some(hwnd), &h).map_err(|e| format!("handler {e}"))?;
            if !SetWindowSubclass(hwnd, Some(subclass), 0x4C50, 0).as_bool() { return Err("subclass failed".into()); }
            let _ = update.Update(None::<&IDirectManipulationFrameInfoProvider>);
            let _ = CTX.set(ctx.clone());
            DM.with(|d| *d.borrow_mut() = Some(Dm { _manager: manager, update, viewport }));
            OK.store(true, Ordering::SeqCst);
        }
        Ok(())
    }
    pub fn ok() -> bool { OK.load(Ordering::SeqCst) }
    pub fn active() -> bool { ACTIVE.load(Ordering::SeqCst) }
    pub fn set_dpr(p: f32) { *DPR.lock().unwrap() = p; }
    /// Advance Direct Manipulation by one frame (call once per UI frame).
    pub fn tick() { if ok() && active() { DM.with(|d| { if let Some(dm) = d.borrow().as_ref() { unsafe { let _ = dm.update.Update(None::<&IDirectManipulationFrameInfoProvider>); } } }); } }
    /// (pan dx px, pan dy px, zoom ratio) accumulated since the last call; physical pixels.
    pub fn take() -> (f32, f32, f32) { ACC.lock().unwrap().take() }
    #[allow(dead_code)] fn _b(_: BOOL) {}
}
#[cfg(windows)] pub use imp::*;

#[cfg(not(windows))]
pub fn init(_h: isize, _c: &egui::Context) -> Result<(), String> { Err("not windows".into()) }
#[cfg(not(windows))] pub fn ok() -> bool { false }
#[cfg(not(windows))] pub fn active() -> bool { false }
#[cfg(not(windows))] pub fn set_dpr(_p: f32) {}
#[cfg(not(windows))] pub fn tick() {}
#[cfg(not(windows))] pub fn take() -> (f32, f32, f32) { (0.0, 0.0, 1.0) }
