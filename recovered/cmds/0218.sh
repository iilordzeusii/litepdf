ls /usr/lib/x86_64-linux-gnu | grep -iE "libGL\b|libGL\.|libGLX|swrast|libEGL|dri" | head; ls /usr/lib/x86_64-linux-gnu/dri 2>/dev/null | head -3; Xvfb -help 2>&1 | grep -i glx | head -2
