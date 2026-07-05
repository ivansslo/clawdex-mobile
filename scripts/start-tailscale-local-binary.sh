#!/usr/bin/env bash
set -euo pipefail

# Run the Clawdex Rust bridge as a local binary, reachable from your phone
# through Tailscale. This is meant for local machines, not Render.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -L)"
BRIDGE_DIR="$ROOT_DIR/services/rust-bridge"
BINARY_PATH="$BRIDGE_DIR/target/release/codex-rust-bridge"
SECURE_ENV_FILE="$ROOT_DIR/.env.secure"

usage() {
  cat <<'USAGE'
Usage: ./scripts/start-tailscale-local-binary.sh [--build] [--no-build]

Starts codex-rust-bridge as a local binary and exposes it on your Tailscale IP.

Options:
  --build     Always build the release binary before starting
  --no-build  Do not build; fail if target/release/codex-rust-bridge is missing
  -h, --help  Show this help

Useful env overrides:
  BRIDGE_PORT=8787
  BRIDGE_PREVIEW_PORT=8788
  BRIDGE_AUTH_TOKEN=<secret>
  BRIDGE_WORKDIR=/path/to/project
  CODEX_CLI_BIN=codex
USAGE
}

BUILD_MODE="auto"
for arg in "$@"; do
  case "$arg" in
    --build) BUILD_MODE="always" ;;
    --no-build) BUILD_MODE="never" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -f "$SECURE_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$SECURE_ENV_FILE"
  set +a
fi

if ! command -v tailscale >/dev/null 2>&1; then
  echo "error: tailscale CLI tidak ditemukan." >&2
  echo "Install Tailscale: https://tailscale.com/download" >&2
  exit 1
fi

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
if [[ -z "$TAILSCALE_IP" ]]; then
  echo "error: Tailscale belum aktif/login." >&2
  echo "Jalankan: tailscale up" >&2
  exit 1
fi

if [[ "$BUILD_MODE" == "always" || ( "$BUILD_MODE" == "auto" && ! -x "$BINARY_PATH" ) ]]; then
  if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo/Rust tidak ditemukan, dan binary belum ada." >&2
    echo "Install Rust: https://rustup.rs" >&2
    exit 1
  fi
  echo "Building Rust bridge release binary..."
  (cd "$BRIDGE_DIR" && cargo build --release --locked)
elif [[ "$BUILD_MODE" == "never" && ! -x "$BINARY_PATH" ]]; then
  echo "error: binary tidak ditemukan: $BINARY_PATH" >&2
  echo "Jalankan tanpa --no-build atau pakai --build." >&2
  exit 1
fi

chmod +x "$BINARY_PATH"

export BRIDGE_HOST="${BRIDGE_HOST:-$TAILSCALE_IP}"
export BRIDGE_PORT="${BRIDGE_PORT:-8787}"
export BRIDGE_PREVIEW_PORT="${BRIDGE_PREVIEW_PORT:-$((BRIDGE_PORT + 1))}"
export BRIDGE_CONNECT_URL="${BRIDGE_CONNECT_URL:-http://$TAILSCALE_IP:$BRIDGE_PORT}"
export BRIDGE_PREVIEW_CONNECT_URL="${BRIDGE_PREVIEW_CONNECT_URL:-http://$TAILSCALE_IP:$BRIDGE_PREVIEW_PORT}"
export BRIDGE_WORKDIR="${BRIDGE_WORKDIR:-$ROOT_DIR}"
export BRIDGE_ALLOW_QUERY_TOKEN_AUTH="${BRIDGE_ALLOW_QUERY_TOKEN_AUTH:-false}"
export BRIDGE_DISABLE_TERMINAL_EXEC="${BRIDGE_DISABLE_TERMINAL_EXEC:-false}"
export BRIDGE_TERMINAL_ALLOWED_COMMANDS="${BRIDGE_TERMINAL_ALLOWED_COMMANDS:-pwd,ls,cat,git}"
export BRIDGE_SHOW_PAIRING_QR="${BRIDGE_SHOW_PAIRING_QR:-true}"

if [[ -z "${BRIDGE_AUTH_TOKEN:-}" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    export BRIDGE_AUTH_TOKEN="$(openssl rand -hex 24)"
  else
    export BRIDGE_AUTH_TOKEN="clawdex-$(date +%s)-$RANDOM"
  fi
  echo "warning: BRIDGE_AUTH_TOKEN tidak diset; memakai token sementara untuk sesi ini." >&2
  echo "Simpan token permanen di .env.secure agar tidak berubah setiap start." >&2
fi

if ! command -v "${CODEX_CLI_BIN:-codex}" >/dev/null 2>&1; then
  echo "warning: Codex CLI tidak ditemukan: ${CODEX_CLI_BIN:-codex}" >&2
  echo "Bridge bisa start gagal jika engine Codex aktif. Install/atur CODEX_CLI_BIN dulu." >&2
fi

cat <<INFO

Starting Clawdex Rust bridge via Tailscale...
  Bind host:        $BRIDGE_HOST
  Bridge URL:       $BRIDGE_CONNECT_URL
  Preview URL:      $BRIDGE_PREVIEW_CONNECT_URL
  Workdir:          $BRIDGE_WORKDIR
  Auth token:       $BRIDGE_AUTH_TOKEN

Dari HP yang sudah login Tailscale, pakai Bridge URL di atas.
Health check:
  curl "$BRIDGE_CONNECT_URL/health"

INFO

exec "$BINARY_PATH"
