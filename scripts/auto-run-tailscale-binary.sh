#!/usr/bin/env bash
set -euo pipefail

# One-command setup + start for Clawdex local Rust bridge over Tailscale.
# This automates:
#   cp docs/tailscale-local-binary.env.example .env.secure
#   npm run bridge:tailscale:binary:build
#
# Note: bridge:tailscale:binary:build builds and then starts the bridge in the
# foreground, so running bridge:tailscale:binary immediately after it would start
# a second bridge on the same port. Use --no-build if you only want to start an
# already-built binary.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -L)"
ENV_EXAMPLE="$ROOT_DIR/docs/tailscale-local-binary.env.example"
ENV_FILE="$ROOT_DIR/.env.secure"

usage() {
  cat <<'USAGE'
Usage: ./scripts/auto-run-tailscale-binary.sh [options]

Options:
  --build       Build release binary and start bridge (default)
  --no-build    Start existing binary without rebuilding
  --force-env   Overwrite .env.secure from docs/tailscale-local-binary.env.example
  --no-token    Do not auto-replace placeholder BRIDGE_AUTH_TOKEN
  -h, --help    Show this help

Examples:
  ./scripts/auto-run-tailscale-binary.sh
  npm run tailscale:auto
  npm run tailscale:auto:no-build
USAGE
}

MODE="build"
FORCE_ENV="false"
AUTO_TOKEN="true"

for arg in "$@"; do
  case "$arg" in
    --build) MODE="build" ;;
    --no-build) MODE="no-build" ;;
    --force-env) FORCE_ENV="true" ;;
    --no-token) AUTO_TOKEN="false" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

cd "$ROOT_DIR"

if [[ ! -f "$ENV_EXAMPLE" ]]; then
  echo "error: env example tidak ditemukan: $ENV_EXAMPLE" >&2
  exit 1
fi

if [[ "$FORCE_ENV" == "true" || ! -f "$ENV_FILE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  echo "Created .env.secure from docs/tailscale-local-binary.env.example"
else
  echo ".env.secure sudah ada; tidak dioverwrite. Pakai --force-env untuk overwrite."
fi

if [[ "$AUTO_TOKEN" == "true" ]]; then
  if grep -q '^BRIDGE_AUTH_TOKEN=clawdex_change_me_to_a_long_random_secret$' "$ENV_FILE"; then
    if command -v openssl >/dev/null 2>&1; then
      TOKEN="clawdex_$(openssl rand -hex 24)"
    else
      TOKEN="clawdex_$(date +%s)_$RANDOM$RANDOM"
    fi

    python3 - "$ENV_FILE" "$TOKEN" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
token = sys.argv[2]
lines = path.read_text().splitlines()
out = []
replaced = False
for line in lines:
    if line.startswith('BRIDGE_AUTH_TOKEN='):
        out.append(f'BRIDGE_AUTH_TOKEN={token}')
        replaced = True
    else:
        out.append(line)
if not replaced:
    out.append(f'BRIDGE_AUTH_TOKEN={token}')
path.write_text('\n'.join(out) + '\n')
PY
    echo "Generated BRIDGE_AUTH_TOKEN otomatis di .env.secure"
  fi
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "error: npm tidak ditemukan." >&2
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  echo "error: tailscale CLI tidak ditemukan." >&2
  echo "Install Tailscale: https://tailscale.com/download" >&2
  exit 1
fi

if [[ -z "$(tailscale ip -4 2>/dev/null | head -n1 | tr -d '[:space:]' || true)" ]]; then
  echo "error: Tailscale belum aktif/login." >&2
  echo "Jalankan: tailscale up" >&2
  exit 1
fi

if [[ "$MODE" == "build" ]]; then
  echo "Running: npm run bridge:tailscale:binary:build"
  exec npm run bridge:tailscale:binary:build
fi

echo "Running: npm run bridge:tailscale:binary"
exec npm run bridge:tailscale:binary
