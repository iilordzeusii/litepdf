cd /tmp; B=https://chromium.googlesource.com/chromium/src/+/HEAD
curl -sL "$B/ui/events/blink/web_input_event.cc?format=TEXT" | base64 -d > wie.cc; grep -n -i -E 'precise|MouseWheelEvent|offset|kScrollBy|WheelEvent' wie.cc | head -40
grep -rn "ScrollByPrecisePixel\|has_precise" /dev/null; curl -sL "$B/content/browser/renderer_host/render_widget_host_view_aura.cc?format=TEXT" | base64 -d | grep -n -i -E 'OnScrollEvent|OnMouseEvent|MouseWheel|precise' | head -20
grep -n -i -E 'tp_tau|sanim2|initial_slope|slope' /tmp/scratch/app/src/app.rs | head -40
