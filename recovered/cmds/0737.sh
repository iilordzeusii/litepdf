cd /tmp; sed -n 2188,2232p ih.cc; curl -sL "https://chromium.googlesource.com/chromium/src/+/HEAD/cc/animation/scroll_offset_animation_curve_factory.cc?format=TEXT" | base64 -d | sed -n 1,80p
