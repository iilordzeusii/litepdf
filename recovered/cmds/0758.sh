cd /tmp; B=https://chromium.googlesource.com/chromium/src/+/HEAD
for p in ui/base/win/direct_manipulation.cc ui/base/win/direct_manipulation.h; do curl -sL "$B/$p?format=TEXT" | base64 -d > dm_$(basename $p); done; wc -l dm_*; grep -n -i -E 'DM_CONFIGURATION|Fling|inertia|Translation|scale|kDefault|OnContentUpdated|SetDeviceScaleFactor|PrecisionTouchpad|ScrollGranularity|momentum' dm_direct_manipulation.cc | head -60
curl -sL "$B/ui/aura/window_tree_host_platform.cc?format=TEXT" | base64 -d | grep -n -i 'direct' | head -3
curl -sL "$B/ui/views/win/hwnd_message_handler.cc?format=TEXT" | base64 -d > hmh.cc; grep -n -i 'DirectManipulation\|OnPointerEvent\|kPrecision\|IsPrecision\|ScrollEvent' hmh.cc | head -40
