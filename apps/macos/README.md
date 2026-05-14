# Clawdex Desktop

Native macOS menu-bar app for running the Clawdex bridge without asking Mac users to operate the npm CLI directly.

Development:

```sh
swift run --package-path apps/macos ClawdexDesktop
```

The app looks for the bridge binary in this order:

1. `CLAWDEX_BRIDGE_BIN`
2. `Clawdex.app/Contents/Resources/codex-rust-bridge`
3. `vendor/bridge-binaries/<target>/codex-rust-bridge`
4. `services/rust-bridge/target/release/codex-rust-bridge`
5. `services/rust-bridge/target/debug/codex-rust-bridge`

Packaged app build:

```sh
npm run desktop:mac:bundle
```

That creates `dist/macos/Clawdex.app` and bundles the release Rust bridge binary into the app resources.
