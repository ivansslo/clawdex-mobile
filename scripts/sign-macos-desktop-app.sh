#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -L)"
APP_PATH="${1:-$ROOT_DIR/dist/macos/Clawdex.app}"
IDENTITY="${CLAWDEX_CODESIGN_IDENTITY:-}"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  echo "Run npm run desktop:mac:bundle first." >&2
  exit 1
fi

if [ -z "$IDENTITY" ]; then
  IDENTITY="$(
    security find-identity -v -p codesigning |
      awk -F '"' '/Developer ID Application/ { print $2; exit }'
  )"
fi

if [ -z "$IDENTITY" ]; then
  IDENTITY="$(
    security find-identity -v -p codesigning |
      awk -F '"' '/Apple Development/ { print $2; exit }'
  )"
fi

if [ -z "$IDENTITY" ]; then
  echo "No code signing identity found." >&2
  echo "Install a Developer ID Application certificate for distribution, or set CLAWDEX_CODESIGN_IDENTITY='-' for an ad-hoc local signature." >&2
  exit 1
fi

TIMESTAMP_ARGS=(--timestamp=none)
if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
  TIMESTAMP_ARGS=(--timestamp)
fi

SIGN_ARGS=(--force --options runtime "${TIMESTAMP_ARGS[@]}" --sign "$IDENTITY")

echo "Signing $APP_PATH"
echo "Identity: $IDENTITY"

if [ -f "$APP_PATH/Contents/Resources/codex-rust-bridge" ]; then
  codesign "${SIGN_ARGS[@]}" "$APP_PATH/Contents/Resources/codex-rust-bridge"
fi

codesign "${SIGN_ARGS[@]}" "$APP_PATH/Contents/MacOS/ClawdexDesktop"
codesign "${SIGN_ARGS[@]}" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp|Runtime" || true

echo "Signed $APP_PATH"
