# SmartHalo 2 — Pairing, password and recovery

> The device's password authentication and how to re-pair your **own** SmartHalo 2 with a new client.
> Source: `shapp/src/auth.c`, `device.c`, `record.*` (nRF side) and the official app.

## Model

- The device stores a **password of ≤32 bytes** in flash (FDS record `KEY_PASSWORD`).
- `authenticate` (`0,3`) compares the received payload byte by byte with the stored password (exact
  length). On a match: permission `0x01` + the UP channel is enabled.
- If **no password** is stored (`auth_password_len == 0`), `authenticate` with an **empty** payload
  succeeds. This is the "unpaired" state.
- `setPassword` (`0,4`) sets (`len 32`, optionally `32+crc16`) or clears (`len 0`) the password. It
  **requires an authenticated session** (permission mask active). Clearing it un-pairs the device and
  resets its name to `"smarthalo"`.

## Normal first pairing (what the app did)

1. ECDH→AES handshake (see `ble-link.md` §5).
2. `authenticate` with an empty password (unpaired device) → OK.
3. The app generates a **random 32-character password**, saves it in its local storage and sends it
   with `setPassword`.
4. From then on, it reconnects and calls `authenticate` with that saved password.

> What this means for an open-source alternative: **the client generates and keeps** its own 32-byte
> password per device, as the app did. If the device is already paired with the official app (a
> password the client doesn't have), it must be **recovered** first.

## Recovering a device that is already paired (unknown password)

The firmware includes an **unauthenticated reset** path in service 0 (registered with permission 0,
so it's always accessible):

1. `getSeed` (`0,6`) → the device returns its current 4-byte **seed**.
2. Compute the challenge = **`SHA-256( seed(4) || salt(16) )`** (32 bytes).
   - The 16-byte `salt` is a firmware constant (in `auth.c`, definition of `auth_salt`, around line
     198). The iOS app includes it in `FirmwareConstants.swift`; the JS tools read it from the firmware
     source.
3. `resetPassword` (`0,7`) + `challenge(32)`. If it matches, the device **clears the password** and
   is left unpaired. After this, an empty `authenticate` works → `setPassword` with the new password.

### Important caveats

- This path lowers the anti-theft protection: anyone within BLE range who has the salt (public) and
  the seed (which the device hands out) can un-pair the device. The firmware's own README points
  this out and suggests adding a delay (1 hour to 1 week) before allowing it. Use it only to recover
  your own device.
- The seed is randomized on every connection and `getSeed`, so read it **live** right before computing
  the challenge. An old seed won't work.

## Alternative route: DFU

If the reset challenge weren't available in a given device's build, the firmware README mentions
recovering through **DFU** (adding a reset command). That carries a risk of bricking the device, and
the **bootloader signing keys were not released**, so custom firmware can't be signed. Recovery
therefore doesn't depend on DFU; it uses the reset challenge over BLE.
