# sh2-linux-client

BLE client for Linux (BlueZ over D-Bus, **no root needed**) on top of `sh2-core`. Transport plus
scan and recovery/pairing tools for your own SmartHalo 2.

## Requirements
- A working Bluetooth adapter (`bluetoothctl list` shows `hci0`) and the `bluetooth` service running.
- Node ≥ 22. Run `npm install` (node-ble + dbus-next). The native `usocket` package **is not needed**
  (node-ble uses `StartNotify`, with no file-descriptor passing).
- The SmartHalo 2 firmware source, for recovery: set `SH2_FIRMWARE_SRC` to the path of your copy of
  `auth.c`.

## Usage

```bash
# 1) Find the SmartHalo (tap or charge it so it advertises)
node bin/sh2-scan.mjs 30          # scans for 30s, marks likely SmartHalos with >>>

# 2) Recover access: reset-challenge + re-pair with a new password
export SH2_FIRMWARE_SRC=/path/to/auth.c
node bin/sh2-pair.mjs <MAC>       # prints the NEW 32-char password -> SAVE IT
node bin/sh2-pair.mjs <MAC> --password MyPassword32CharsExactly........
```

`sh2-pair` does: connect → `getSeed`+`resetPassword(SHA256(seed‖salt))` (unpairs the device, without
needing the old password) → handshake with an empty password → `setPassword(new)`.
The `salt` isn't hard-coded here: it comes from the firmware source through `SH2_FIRMWARE_SRC`.

## Modules
- `src/dbus-transport.mjs` — `DbusTransport`: implements the `sh2-core` Transport interface
  (`writeNoResponse`, `subscribe`) on top of node-ble.
- `src/find-salt.mjs` — reads the 16-byte salt from `auth.c`.
- `bin/sh2-scan.mjs`, `bin/sh2-pair.mjs` — CLIs.

## Status
- The transport is validated over D-Bus, and the recovery logic is tested in `sh2-core`.
- Known risk: if `resetPassword` returns FAIL, your unit's salt or algorithm differs from the public
  firmware. Stop and check (nothing else gets changed).
