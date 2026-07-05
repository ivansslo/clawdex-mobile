# Tailscale Local Binary Bridge

Mode ini menjalankan `codex-rust-bridge` sebagai binary lokal dan membuatnya bisa diakses dari HP melalui Tailscale.


## Auto run satu perintah

Kalau ingin otomatis copy env example, generate token jika masih placeholder, lalu build + start bridge:

```bash
npm run tailscale:auto
```

Untuk start tanpa rebuild:

```bash
npm run tailscale:auto:no-build
```

Untuk overwrite `.env.secure` dari example lalu start ulang:

```bash
npm run tailscale:auto:force-env
```

Catatan: `bridge:tailscale:binary:build` sudah melakukan build dan langsung menjalankan bridge di foreground. Jadi tidak perlu menjalankan `bridge:tailscale:binary` lagi setelahnya kecuali proses pertama sudah dihentikan.

## 1. Login Tailscale di laptop/PC dan HP

```bash
tailscale up
tailscale ip -4
```

HP harus login ke akun/tailnet Tailscale yang sama.

## 2. Siapkan env

```bash
cp docs/tailscale-local-binary.env.example .env.secure
```

Edit `.env.secure`, minimal ganti:

```env
BRIDGE_AUTH_TOKEN=token_rahasia_yang_panjang
```

## 3. Start binary bridge

```bash
npm run bridge:tailscale:binary:build
```

Atau setelah binary sudah pernah dibuild:

```bash
npm run bridge:tailscale:binary
```

Script akan otomatis:

- mengambil IP Tailscale dari `tailscale ip -4`
- bind bridge ke IP tersebut
- set `BRIDGE_CONNECT_URL=http://<tailscale-ip>:8787`
- set preview localhost ke `http://<tailscale-ip>:8788`
- menampilkan QR pairing jika enabled

## 4. Test dari laptop

```bash
curl "http://$(tailscale ip -4 | head -n1):8787/health"
```

## 5. Setting di aplikasi HP

Gunakan:

```text
Bridge URL: http://<TAILSCALE_IP>:8787
Token: isi BRIDGE_AUTH_TOKEN dari .env.secure
```

Contoh:

```text
Bridge URL: http://100.101.102.103:8787
Token: clawdex_change_me_to_a_long_random_secret
```

## Catatan

- Ini untuk lokal via Tailscale, bukan Render public URL.
- Render tidak bisa mengakses `localhost` laptop kamu. Kalau ingin tetap memakai Render, container Render harus join tailnet dengan auth key Tailscale, tetapi untuk Clawdex bridge lebih simpel dan aman menjalankan binary langsung di laptop/PC.
