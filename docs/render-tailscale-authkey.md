# Render + Tailscale Auth Key

Gunakan mode ini kalau Render service perlu join ke Tailscale tailnet memakai auth key.

## 1. Buat Tailscale auth key

Di Tailscale Admin Console:

1. Buka **Settings → Keys**
2. Klik **Generate auth key**
3. Disarankan:
   - **Reusable**: off, kecuali perlu deploy berulang dengan key sama
   - **Ephemeral**: on untuk Render instance sementara
   - **Tags**: gunakan tag seperti `tag:server` kalau ACL kamu butuh tag


> Catatan: env lama `TAILSCALE_AUTHKEY`, `TAILSCALE_HOSTNAME`, dan `TAILSCALE_SERVE` masih diterima untuk backward compatibility, tetapi konfigurasi baru memakai `TS_*`.

Copy key yang bentuknya mirip:

```text
tskey-auth-xxxxx
```

## 2. Set Environment Variables di Render

Masuk Render Dashboard:

```text
Service → Environment
```

Tambahkan:

```env
TS_AUTHKEY=tskey-auth-xxxxx
TS_HOSTNAME=tailsup
TS_SERVE=true
```

Env lain tetap:

```env
NODE_VERSION=22.19.0
BRIDGE_AUTH_TOKEN=token_rahasia_bridge
BRIDGE_DISABLE_TERMINAL_EXEC=true
BRIDGE_ALLOW_QUERY_TOKEN_AUTH=false
```

## 3. Render commands

Build Command:

```bash
npm ci --include=dev && npm run build -w @codex/mac-bridge
```

Start Command:

```bash
./scripts/render-start-tailscale-authkey.sh
```

Pre-Deploy Command harus kosong. Jangan isi dengan script local binary Tailscale.

## 4. Deploy ulang

Klik:

```text
Manual Deploy → Clear build cache & deploy
```

## Catatan penting

- Script ini menjalankan `tailscaled` dalam mode userspace karena Render biasanya tidak menyediakan `/dev/net/tun` privileged.
- Service tetap listen ke `$PORT` untuk health check Render.
- Script akan mencoba `tailscale serve` agar service bisa diakses dari tailnet.
- Jika `tailscale serve` gagal karena perbedaan versi CLI, Render URL public tetap jalan. Cek log Render dan `/tmp/tailscaled.log`.
