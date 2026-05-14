#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -L)"
APP_NAME="Clawdex"
APP_DIR="$ROOT_DIR/dist/macos/${APP_NAME}.app"
SWIFT_PRODUCT="$ROOT_DIR/apps/macos/.build/release/ClawdexDesktop"
SWIFT_RESOURCE_BUNDLE="$ROOT_DIR/apps/macos/.build/release/ClawdexDesktop_ClawdexDesktop.bundle"
BRIDGE_BINARY="$ROOT_DIR/services/rust-bridge/target/release/codex-rust-bridge"

echo "Building Rust bridge..."
cargo build --manifest-path "$ROOT_DIR/services/rust-bridge/Cargo.toml" --release --locked

echo "Building macOS menu-bar app..."
swift build --package-path "$ROOT_DIR/apps/macos" -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$SWIFT_PRODUCT" "$APP_DIR/Contents/MacOS/ClawdexDesktop"
cp "$BRIDGE_BINARY" "$APP_DIR/Contents/Resources/codex-rust-bridge"
if [ -d "$SWIFT_RESOURCE_BUNDLE" ]; then
  cp -R "$SWIFT_RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi
chmod +x "$APP_DIR/Contents/MacOS/ClawdexDesktop"
chmod +x "$APP_DIR/Contents/Resources/codex-rust-bridge"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ClawdexDesktop</string>
  <key>CFBundleIdentifier</key>
  <string>com.clawdex.desktop</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Clawdex</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"
