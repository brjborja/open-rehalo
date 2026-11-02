# sh2-desktop

Desktop GUI (Electron) for the **SmartHalo 2** — scan, recover/pair and control the
light over BLE, built on top of the dependency-free [`sh2-core`](../../sh2-core) protocol
library. Ships with a **mock mode** that runs the whole app against the
[`emulator`](../../emulator) `Sh2Device`, so everything (scan → connect → pair → control)
works end-to-end **without any hardware**.

Electron is used because it is JavaScript — the same language as `sh2-core` — so the
main/Node process can reuse the BLE code and the emulator directly.

## Quick start

```bash
cd clients/desktop
npm install          # Electron, electron-builder, node-ble

npm start            # launches the window (real-BLE mode by default)
npm run start:mock   # launches in MOCK mode (no hardware needed) — start here
```

Mock mode can also be toggled live from the **"Mode"** application menu or the
**Emulator / Real BLE** switch in the header, and forced with `--mock` or `SH2_MOCK=1`.

## What works in mock mode (verified)

The emulator presents a SmartHalo that is already paired with an **unknown** old password
(the realistic "bricked unit" case). The full flow works against it in software:

1. **Scan** → lists the emulated `smarthalo`.
2. **Connect** → opens a `Session` over the emulator's transport.
3. **Recover access** → runs `recovery.recoverAccess` (getSeed → `resetPassword(SHA256(seed‖salt))`
   → handshake("") → `setPassword`), shows the **new 32-char device password**, and lets you
   **copy / save** it to a file.
4. **Controls** (unlocked after pairing): front light on/off + brightness, alarm arm/disarm/report,
   device info. The on-screen halo lights up with the light state.
5. You can **reconnect and authenticate** with the recovered password.

This is exercised by `npm test` (headless, no Electron) and by a packaged-AppImage smoke run.

```bash
npm test             # node --test: drives the real DeviceManager over the emulator
```

## Architecture

Everything above the wire is transport-agnostic — the UI never knows whether it is talking
to hardware or the emulator.

```
renderer (HTML/CSS/JS, no Node)
   │  window.sh2.*  (contextBridge)
preload.js ── ipc ──► main.js (Electron, CJS)
                         │
                   device-manager.mjs      owns Session + recovery (from sh2-core)
                         │  Transport
          ┌──────────────┴───────────────┐
   mock-backend.mjs                 ble-backend.mjs
   (emulator Sh2Device)             (node-ble / BlueZ, reuses
    — no hardware                    clients/linux DbusTransport + find-salt)
```

- `src/device-manager.mjs` — transport-agnostic logic; public methods return `{ ok, … }`.
- `src/backends/mock-backend.mjs` — wraps the emulator's `Sh2Device.bleTransport()`.
- `src/backends/ble-backend.mjs` — real path; lazily loads `node-ble` + the existing
  `DbusTransport` and `find-salt` from `clients/linux` (reused read-only, never modified).

`sh2-core`, `emulator` and `clients/linux` are imported read-only (relative paths in dev,
and copied into the AppImage via electron-builder `extraResources` for the packaged build).

## Build the AppImage

```bash
npm run dist         # electron-builder --linux AppImage
# → dist/rehalo-Desktop-<version>.AppImage
```

Config lives in the `build` field of `package.json` (target AppImage, icon `build/icon.png`,
and `extraResources` that copy `sh2-core`, `emulator` and `clients/linux/src` so mock mode
works inside the packaged app). `asar` is disabled to keep ESM dynamic imports simple.

### Install

```bash
cp dist/rehalo-Desktop-*.AppImage ~/Applications/rehalo-Desktop.AppImage
cp build/icon.png                     ~/Applications/rehalo-desktop.png
chmod +x ~/Applications/rehalo-Desktop.AppImage

# then add a launcher (template provided):
cp packaging/smarthalo2-desktop.desktop ~/.local/share/applications/
# then edit Exec= and Icon= in that file to match where you put them
```

Prefer a versioned filename + stable symlink if you keep multiple builds.

## Real BLE

The real-BLE path (`ble-backend.mjs`) reuses the transport from `clients/linux`. Notes:

- Needs a working BlueZ adapter (`bluetoothctl list`) and the `bluetooth` service running.
- The reset-challenge **salt** comes from the public firmware source: set `SH2_FIRMWARE_SRC`
  to the path of your copy of `auth.c`. Without it, BLE *recovery* is disabled (scan/connect
  still work). Mock mode falls back to a demo salt and is unaffected.
- `resetPassword` returning `FAIL` means your unit's salt/algorithm differs from the public
  firmware — stop and investigate (same risk noted in `clients/linux`).
- From a packaged AppImage the real path also needs `node-ble` and the firmware source, so
  for real hardware prefer running from source (`npm start`).
