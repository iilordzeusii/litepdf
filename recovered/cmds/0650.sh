cd ~/.cargo/registry/src/*/; sed -n 95,120p egui-0.34.3/src/input_state/wheel_state.rs; grep -n 'MouseScrollDelta' -B2 -A22 egui-winit-0.34*/src/lib.rs | sed -n 1,70p
