#!/bin/sh
# Build Ditto.app into build/. Usage: script/build.sh [--run [app args...]]
set -eu
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)/Ditto"

app=build/Ditto.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Ditto"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.rcbran.ditto</string>
  <key>CFBundleName</key><string>Ditto</string>
  <key>CFBundleDisplayName</key><string>Ditto</string>
  <key>CFBundleExecutable</key><string>Ditto</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>$(git rev-list --count HEAD 2>/dev/null || echo 1)</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Ad-hoc signature for now. The Accessibility permission (for auto-paste) resets on each rebuild
# until this is signed with a real certificate.
codesign --force --sign - "$app" >/dev/null
echo "built $app"

if [ "${1:-}" = "--run" ]; then
  shift
  pkill -x Ditto 2>/dev/null || true
  sleep 0.3
  open "$app" --args "$@"
fi
