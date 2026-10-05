cd /tmp; sed -n 262,275p wb.cc; sed -n 2472,2500p ih.cc; B=https://chromium.googlesource.com/chromium/src/+/HEAD
curl -sL "$B/cc/animation/scroll_offset_animation_curve.cc?format=TEXT" | base64 -d > soac.cc; grep -n -E 'kConstantDuration|kDurationDivisor|kInverse|kImpulse|Duration|0\.42|CubicBezier|velocity|ImpulseCurve|kDelayBeforeStart' soac.cc | head -70
