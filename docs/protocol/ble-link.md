# SmartHalo 2 — BLE link layer ("bslink")

> Taken from the public firmware source (`shapp/src/bslink.c`, `bleapp.c`, `auth.c`, `aes.c`) and the
> official app. Verified by cross-reading firmware ↔ app; the write behavior in §3 was validated
> against a real SmartHalo 2.

## 1. Advertising / discovery

- The device advertises its **name** (e.g. "SmartHalo") as `FULL_NAME`.
- Advertised service: **`0x5348`** (`"SH"`, 16-bit range), used only for scan filtering.
- Manufacturer data with company id **`0x0466`**.
- The real data service is the **128-bit vendor GATT** below (not 0x5348).

## 2. GATT service and characteristics

Primary service: **`92540000-d6ed-4617-a4b4-d749f57710ce`**
(base UUID `9254xxxx-d6ed-4617-a4b4-d749f57710ce`; the 4 `xxxx` digits are the short id).

Two full-duplex channels, each with 1 control characteristic + 4 payload characteristics (MTU 20 B):

| Role | Short UUID | Full UUID | Purpose |
| --- | --- | --- | --- |
| **DOWN CTRL**      | `0x0001` | `92540001-…` | Control of the central→device channel and device→central replies |
| DOWN PAYLOAD 0..3  | `0x0010`–`0x0013` | `92540010-…`–`92540013-…` | Data chunks (4×20 = 80 B max) |
| **UP CTRL**        | `0x0101` | `92540101-…` | Control of the channel for unsolicited device→central notifications |
| UP PAYLOAD 0..3    | `0x0110`–`0x0113` | `92540110-…`–`92540113-…` | Notification chunks |

All are READ+WRITE+NOTIFY (UP CTRL can be INDICATE if the firmware is built with `BSLINK_INDICATE`;
in the public build it's NOTIFY). Standard CCCD `0x2902`.

The client must **enable notifications (CCCD)** on: DOWN CTRL, DOWN PAYLOAD 0..3, UP CTRL and UP
PAYLOAD 0..3.

## 3. Message framing

A logical "message" is at most **80 bytes** (`MAX_COMMAND_LENGTH = 80 = 4×20`).

### Sending central → device
1. Write the payload chunks to **DOWN PAYLOAD 0,1,2,3** in order (as many as needed).
   **⚠️ Write WITH Response.** In the firmware (`bleapp.c:700`) the characteristics are added with
   `char_props.write` but **NOT** `write_wo_resp`, so a *Write Without Response* is silently dropped
   (the ring never receives the command → timeout). Validated against a real SmartHalo 2: `getSeed`
   only replies to writes with response. Android is lenient and delivers such writes anyway;
   CoreBluetooth and BlueZ respect the property and drop them.
2. Write **DOWN CTRL** = `[ len, crypted ]` (2 bytes), also with response:
   - `len` = real payload length (after encryption/padding, if any),
   - `crypted` = `1` if encrypted, `0` if in cleartext.
   The CTRL write is what triggers processing on the device (`bslink_recv`).

### Reply / sending device → central (DOWN channel)
- The device NOTIFIES the chunks on **DOWN PAYLOAD 0..3** and then NOTIFIES **DOWN CTRL** with
  `[len, crypted]`, which marks the reply as complete. The central accumulates the payloads and, on
  receiving CTRL, reads them as a reply of length `len`.

### Unsolicited notifications (UP channel)
- Active only **after authentication** (`bslink_onAuth`). Same scheme with UP PAYLOAD/UP CTRL. Used
  for spontaneous device events (e.g. alarm report, state).

## 4. Link encryption

- **AES-128-CBC** with **PKCS#7** padding (last byte = number of padding bytes; always added, even
  on a full block → 16 bytes of padding).
- **Key** = `secret[0:16]`, **IV** = `secret[16:32]` of the 16+16-byte *shared secret*.
- The CTRL `crypted` flag says per frame whether the payload is encrypted. Before the secret is set
  (handshake) frames are in cleartext; after that, encrypted.

## 5. Handshake (setting the shared secret) — service 0 "auth"

Curve **NIST P-256 (secp256r1)**, ECDH. Sequence from the central:

1. **getVersions** `{0,0}` → `[RET_OK, fw(4), bl(4)]` *(cleartext, optional)*.
2. **getPeriphPubKey** `{0,1}` → `[RET_OK, periphPubKey(64), seed(4)]` *(cleartext)*.
   - `periphPubKey` = X||Y coordinates (64 B). `seed` = 4 random bytes from the device.
3. The central generates its **ephemeral P-256 key pair** and computes the **ECDH** with
   `periphPubKey` → 32-byte secret. It then **overwrites bytes [16..19] with the `seed`**. Result:
   `secret[0:16]` = AES key, `secret[16:32]` = IV (its first 4 bytes = seed).
   - *Endianness gotcha*: the firmware reverses the byte order of the public key and secret halves
     (`reverse()` in `auth.c`); the official app uses the key agreement output as is. A new
     implementation must reproduce that convention exactly (see `auth_setCentralPubKey` in `auth.c`).
4. **setCentralPubKey** `{0,2}` + `centralPubKey(64)` → `[RET_OK]` *(cleartext)*. From here on the
   device has the secret set and **expects encrypted frames**.
5. **authenticate** `{0,3}` + `password` → `[RET_OK]` / `[RET_FAIL]` *(encrypted)*. On OK, the
   permission mask `0x01` and the UP channel are enabled. See `pairing.md` for the password.

## 6. Dispatch and permissions

- The **first byte** of the decrypted payload is the **service id**; the **second**, the **command
  id**; the rest, arguments.
- `service 0` → auth (handled by the nRF). `service 7` → nRF only. **Every other service is forwarded
  over UART to the STM32** (which implements light/sound/alarm/display). See `commands.md`.
- Each dispatch entry has a **permission mask**: 0 means always accessible; otherwise the active
  permission (after `authenticate`) must include it. Without authentication → `RET_DENIED`.
- Inactivity timeout: if the central doesn't authenticate within ~60 s of connecting, the device
  kicks it out (`KICKOUT_DELAY`).

## 7. Return codes

| Value | Name | |
| --- | --- | --- |
| 0 | `RET_OK` | success |
| 1 | `RET_FAIL` | generic/unknown failure |
| 2 | `RET_DENIED` | no permission (not authenticated) |
| 3 | `RET_UNIMPLEMENTED` | command not implemented |
| 4 | `RET_UNNECESSARY` | (app side only) not needed |
