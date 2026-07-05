#!/usr/bin/env bash
set -euo pipefail

# Render start wrapper with Tailscale auth-key support.
# - Starts the Node mac-bridge on Render's $PORT for normal Render health checks.
# - If TS_AUTHKEY is set, downloads/starts tailscaled in userspace mode.
# - Optionally tries to expose the Render service inside your tailnet with `tailscale serve`.
#
# Required on Render:
#   TS_AUTHKEY=tskey-auth-...
#
# Optional:
#   TS_HOSTNAME=tailsup
#   TS_SERVE=true
#   TS_SERVE_HTTP_PORT=80

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)"
PORT="${PORT:-8787}"
BRIDGE_HOST="${BRIDGE_HOST:-0.0.0.0}"
BRIDGE_PORT="${BRIDGE_PORT:-$PORT}"
# New short env names use TS_*.
# Backward compatibility: old TAILSCALE_* env names are still accepted.
TS_AUTHKEY="${TS_AUTHKEY:-${TAILSCALE_AUTHKEY:-}}"
TAILSCALE_DIR="${TS_DIR:-${TAILSCALE_DIR:-/tmp/tailscale}}"
TAILSCALE_SOCKET="${TS_SOCKET:-${TAILSCALE_SOCKET:-/tmp/tailscaled.sock}}"
TAILSCALE_STATE="${TS_STATE:-${TAILSCALE_STATE:-/tmp/tailscaled.state}}"
TAILSCALE_HOSTNAME="${TS_HOSTNAME:-${TAILSCALE_HOSTNAME:-tailsup}}"
TAILSCALE_SERVE="${TS_SERVE:-${TAILSCALE_SERVE:-true}}"
TAILSCALE_SERVE_HTTP_PORT="${TS_SERVE_HTTP_PORT:-${TAILSCALE_SERVE_HTTP_PORT:-80}}"

log() {
  printf '[render-tailscale] %s\n' "$*"
}

install_tailscale_binary() {
  if command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1; then
    TAILSCALE_BIN="$(command -v tailscale)"
    TAILSCALED_BIN="$(command -v tailscaled)"
    return 0
  fi

  mkdir -p "$TAILSCALE_DIR"

  local arch pkg_arch latest_url archive extracted_dir
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) pkg_arch="amd64" ;;
    aarch64|arm64) pkg_arch="arm64" ;;
    armv7l) pkg_arch="arm" ;;
    *)
      log "Unsupported architecture for automatic Tailscale install: $arch"
      return 1
      ;;
  esac

  if [[ -x "$TAILSCALE_DIR/tailscale" && -x "$TAILSCALE_DIR/tailscaled" ]]; then
    TAILSCALE_BIN="$TAILSCALE_DIR/tailscale"
    TAILSCALED_BIN="$TAILSCALE_DIR/tailscaled"
    return 0
  fi

  log "Downloading Tailscale userspace binary for $pkg_arch..."
  latest_url="$({
    curl -fsSL https://pkgs.tailscale.com/stable/ \
      | grep -Eo "tailscale_[0-9]+\.[0-9]+\.[0-9]+_${pkg_arch}\.tgz" \
      | sort -V \
      | tail -n1 \
      | sed 's#^#https://pkgs.tailscale.com/stable/#'
  } || true)"

  if [[ -z "$latest_url" ]]; then
    log "Could not resolve latest Tailscale download URL."
    return 1
  fi

  archive="$TAILSCALE_DIR/tailscale.tgz"
  curl -fsSL "$latest_url" -o "$archive"
  tar -xzf "$archive" -C "$TAILSCALE_DIR"
  extracted_dir="$(find "$TAILSCALE_DIR" -maxdepth 1 -type d -name 'tailscale_*' | sort | tail -n1)"

  if [[ -z "$extracted_dir" || ! -x "$extracted_dir/tailscale" || ! -x "$extracted_dir/tailscaled" ]]; then
    log "Downloaded archive did not contain tailscale/tailscaled binaries."
    return 1
  fi

  cp "$extracted_dir/tailscale" "$TAILSCALE_DIR/tailscale"
  cp "$extracted_dir/tailscaled" "$TAILSCALE_DIR/tailscaled"
  chmod +x "$TAILSCALE_DIR/tailscale" "$TAILSCALE_DIR/tailscaled"

  TAILSCALE_BIN="$TAILSCALE_DIR/tailscale"
  TAILSCALED_BIN="$TAILSCALE_DIR/tailscaled"
}

start_tailscale() {
  if [[ -z "${TS_AUTHKEY:-}" ]]; then
    log "TS_AUTHKEY is not set; starting normal Render web service without Tailscale."
    return 0
  fi

  install_tailscale_binary || {
    log "Failed to install Tailscale binary; continuing without Tailscale."
    return 0
  }

  log "Starting tailscaled userspace daemon..."
  "$TAILSCALED_BIN" \
    --tun=userspace-networking \
    --socket="$TAILSCALE_SOCKET" \
    --state="$TAILSCALE_STATE" \
    --socks5-server=127.0.0.1:1055 \
    > /tmp/tailscaled.log 2>&1 &
  TAILSCALED_PID=$!

  for _ in $(seq 1 40); do
    if "$TAILSCALE_BIN" --socket="$TAILSCALE_SOCKET" status >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done

  log "Joining tailnet with auth key as hostname: $TAILSCALE_HOSTNAME"
  "$TAILSCALE_BIN" --socket="$TAILSCALE_SOCKET" up \
    --authkey="$TS_AUTHKEY" \
    --hostname="$TAILSCALE_HOSTNAME" \
    --accept-routes="${TAILSCALE_ACCEPT_ROUTES:-false}"

  log "Tailscale IP(s): $($TAILSCALE_BIN --socket="$TAILSCALE_SOCKET" ip 2>/dev/null | tr '\n' ' ' || true)"
}

try_tailscale_serve() {
  if [[ -z "${TS_AUTHKEY:-}" || "$TAILSCALE_SERVE" != "true" ]]; then
    return 0
  fi

  local target="http://127.0.0.1:${PORT}"
  log "Trying to expose $target inside tailnet with tailscale serve..."

  # Tailscale serve CLI syntax has changed across releases, so try a few common forms.
  if "$TAILSCALE_BIN" --socket="$TAILSCALE_SOCKET" serve --bg --http="$TAILSCALE_SERVE_HTTP_PORT" "$target"; then
    log "tailscale serve configured on HTTP port $TAILSCALE_SERVE_HTTP_PORT."
    return 0
  fi

  if "$TAILSCALE_BIN" --socket="$TAILSCALE_SOCKET" serve --bg "$target"; then
    log "tailscale serve configured."
    return 0
  fi

  if "$TAILSCALE_BIN" --socket="$TAILSCALE_SOCKET" serve --bg "${PORT}"; then
    log "tailscale serve configured for local port $PORT."
    return 0
  fi

  log "tailscale serve could not be configured automatically. Render URL still works. Check /tmp/tailscaled.log."
}

shutdown() {
  log "Shutting down..."
  if [[ -n "${APP_PID:-}" ]]; then
    kill "$APP_PID" 2>/dev/null || true
  fi
  if [[ -n "${TAILSCALED_PID:-}" ]]; then
    kill "$TAILSCALED_PID" 2>/dev/null || true
  fi
}
trap shutdown TERM INT

cd "$ROOT_DIR"

start_tailscale

export BRIDGE_HOST BRIDGE_PORT
log "Starting mac-bridge on ${BRIDGE_HOST}:${BRIDGE_PORT}"
npm run start -w @codex/mac-bridge &
APP_PID=$!

# Give Fastify a moment to bind before configuring serve.
sleep 2
try_tailscale_serve || true

wait "$APP_PID"
