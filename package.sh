#!/bin/bash
# Compila y empaqueta SimpleMounter.app
set -e
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"

# Binario universal: funciona en Apple Silicon (arm64) e Intel (x86_64).
swift build -c release --arch arm64 --arch x86_64

# Con build universal el binario queda en .build/apple/Products/Release
BIN=".build/apple/Products/Release/SimpleMounter"
[ -f "$BIN" ] || BIN=".build/release/SimpleMounter"

APP="SimpleMounter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/SimpleMounter"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>SimpleMounter</string>
    <key>CFBundleDisplayName</key>       <string>SimpleMounter</string>
    <key>CFBundleIdentifier</key>        <string>local.simplemounter</string>
    <key>CFBundleVersion</key>           <string>0.0624</string>
    <key>CFBundleShortVersionString</key><string>0.0624</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleExecutable</key>        <string>SimpleMounter</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

# Firma ad-hoc para que macOS la ejecute sin advertencias de binario sin firmar.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Listo: $(pwd)/$APP"
