# SmartHalo 2 — Official app API notes (Android)

> Cloud API and BLE notes from reverse engineering the official Android app (`bike.smarthalo.app`,
> version 1.18.0), checked against `sh2-core` and `docs/protocol`.

## 1. Backend hostnames

Base of the cloud API:

- **`https://api.smarthalo.bike/`** — main REST API (production).
- `devapi.smarthalo.bike` — development environment (cleartext allowed for this host only).

Auxiliary hosts:

| Host | Use |
| --- | --- |
| `https://valhalla.smarthalo.bike/valhalla/` | Routing/directions (Valhalla engine). dev=`valhalla-dev`, staging=`valhalla-staging` |
| `https://mobile.smarthalo.bike/` | Feature/demo pages (`/features/android-<ver>/`) and integrations (deeplink `smarthalo://mobile.smarthalo.bike/integration/`) |
| `https://www.strava.com/` | Strava OAuth + activity upload |

The OTA firmware binary is downloaded from an **absolute URL** returned by the backend (field
`firmware_url`), not from a fixed host (see §2, Firmware / OTA).

## 2. REST API — endpoints and JSON shapes

### Headers

- **`x-consumer-token`** (gateway key built into the official app; value not included here).
  **Required on ALL v2 endpoints and also on login/signup/refresh.** The v1 endpoints (`whoami`,
  `update`, `rides`, `checkEmail`, `forgot`) don't ask for it.
- **`x-access-token`** = `access_jwt` from login. Authenticates the user.
- The app adds `Accept: application/json` and `Content-Type: application/json` to every request.

### Auth (no `x-access-token`)

| Method | Path | Headers | Body | Response |
| --- | --- | --- | --- | --- |
| POST | `auth/local/login` | `x-consumer-token` | `{email, password}` | `UserResponse` = `{access_jwt, refresh_jwt, user:SHUser}` |
| POST | `auth/local/signup` | `x-consumer-token` | `{firstName, lastName, email, password, dateOfBirth, language}` | `UserResponse` |
| POST | `auth/local/refresh_tokens` | `x-consumer-token` | `{data:{refresh_jwt}}` | `{data:[{access_jwt, refresh_jwt}]}` |
| POST | `auth/local/checkEmail` | — | `{email}` | raw `String` (scalar) |
| POST | `auth/forgot` | — | `{email, language}` | raw `String` (scalar) |

> Refresh uses a generic envelope: request `{data:{...}}`, response `{data:[{...}]}` (an array; take
> `data[0]`).

### User (`x-access-token`)

| Method | Path | Headers | Body | Response |
| --- | --- | --- | --- | --- |
| GET | `api/v1/users/whoami` | `x-access-token` | — | `SHUser` |
| **PUT** | `api/v1/users/update` | `x-access-token` | `{user:SHUser}` | `String` |
| POST | `api/v1/users/sendConfirm` | `x-access-token` | `{email, language}` | `String` |

### Device configs (`x-access-token` + `x-consumer-token`)

| Method | Path | Body | Response |
| --- | --- | --- | --- |
| GET | `api/v2/users/{userId}/configs` | — | `{success:bool, configs:{String:String}}` |
| PUT | `api/v2/users/{userId}/configs` | `{user_id, configs:{String:String}}` | `{success:bool}` |
| DELETE | `api/v2/users/{userId}/configs` | `{user_id, configs:{String:String}}` | `Boolean` |

### Rides

| Method | Path | Headers | Response |
| --- | --- | --- | --- |
| GET | `api/v1/users/rides` | `x-access-token` | `[SHPastRide]` |
| POST | `api/v1/users/rides/sync` | `x-access-token` | `[[RideMarker]]` (body: `[RideUploadPayload]`) |
| GET | `/v2/users/me/rides/{ride_id}?include=` | +`x-consumer-token` | `{data:[CloudRide]}` |
| PATCH | `/v2/users/me/rides/{ride_id}` | +`x-consumer-token` | `{data:[CloudRide]}` (body `{data:PatchRideRequest}`) |
| DELETE | `api/v2/rides/{ride_id}` | +`x-consumer-token` | `Boolean` |

`SHPastRide`: `id, stamp(PK), start, end, createdAt, updatedAt, duration, distance, averageSpeed,
elevation, calories, co2, user_id, integration`.

### Favourites (`x-access-token` + `x-consumer-token`)

| Method | Path | Body |
| --- | --- | --- |
| GET | `api/v2/users/{userId}/favourites` | → `[UserFavourite]` |
| POST | `api/v2/users/{userId}/favourites` | `{user_id, favourite_type, address, label, lat, lng}` → `Boolean` |
| DELETE | `api/v2/users/{userId}/favourites` | form-urlencoded `favourite_id` → `Boolean` |

### Firmware / OTA (`x-consumer-token` + `x-access-token`)

| Method | Path | Query | Response |
| --- | --- | --- | --- |
| GET | `v2/dfu` | `firmware_version`, `device_model` | `{data:[{firmware_version, firmware_url, firmware_description}]}` |
| GET | `<firmware_url>` (absolute URL) | — | binary |

### Device connections / activities

| Method | Path | Headers | Body |
| --- | --- | --- | --- |
| POST | `api/v2/device_connections` | `x-access-token`+`x-consumer-token` | `{user_id, event_type, device_id, device_version, product_serial, pcba_serial, lock_serial}` |
| POST | `v2/activities` | `x-consumer-token`+`x-access-token` | `{data:{type, attributes}}` |

### External services

- **Valhalla**: bike routing against `valhalla.smarthalo.bike/valhalla/`.
- **Strava**: OAuth `www.strava.com/oauth/mobile/authorize` (scope `read,activity:write`, redirect
  `smarthalo://mobile.smarthalo.bike/integration/strava`) + ride upload.

### `SHUser` model

`key (PK, required), email (required), firstName (required), lastName (required), password (not
stored), id, dateOfBirth, deviceId, deviceModel (sent as "deviceVersion"), devicePass, picture,
language, gender (0=man, 1=woman, 2=trans/other, 3=undisclosed), height, weight, heightMetric,
weightMetric, distanceMetric, isConfirmed, authLevel, created_at (not stored)`.

## 3. TLS

**The official app has no certificate pinning.** It uses the platform's default TLS behavior, with no
custom trust configuration.

- The production host `api.smarthalo.bike` doesn't allow cleartext; only `devapi.smarthalo.bike`
  (subdomains included) does.
- Android 7 and later ignore user-installed CAs for app traffic unless the app declares them, and the
  official app doesn't. A server answering for `api.smarthalo.bike` would need a certificate that the
  phone's system store trusts.

The clients in this repo don't need any of that: they point directly at `sh2-server`.

## 4. BLE — check against `docs/protocol` / `sh2-core`

**Everything matches the protocol notes. The app adds no new UUIDs or commands.**

### UUIDs (match `docs/protocol/ble-link.md`)

Service: `92540000-d6ed-4617-a4b4-d749f57710ce`. Characteristics:
`SHLINKCTRL 92540001`, `SHLINKPAYLOAD0..3 92540010-13`, `SHLINKUPCTRL 92540101`,
`SHLINKUPPAYLOAD0..3 92540110-13`. CCCD `00002902-…`. Exactly the table in ble-link.md.

### Encryption (matches `ble-link.md §4-5`)

- ECDH **secp256r1 (P-256)**.
- `shared secret` = ECDH (32 B); **bytes [16..19] are overwritten with the 4-byte `seed`** that the
  device delivers in `getPeriphPubKey`. `AES key = secret[0:16]`, `IV = secret[16:32]`.
- **AES-128-CBC / PKCS5**.
- **CRC-CCITT-16** checksum.
- Packet header `[len, crypted]`; `crypted==1` → decrypt. Same as ble-link.md.

### Handshake (matches `ble-link.md §5`)

`getPeriphPubKey {0,1}` → check that `deviceId` is a prefix of the hex of the device's public key →
derive the secret from `pubKey(64)` and `seed(4)` → `setCentralPubKey {0,2}` + own public key (64 B) →
`authenticate {0,3}` + password.

### Commands (match `docs/protocol/commands.md`)

The app defines service 0 (`getVersions {0,0}`, `getPeriphPubKey {0,1}`, `setCentralPubKey {0,2}`,
`authenticate {0,3}`, `setPassword {0,4}`), service 1 (UI, `{1,0}`..`{1,37}`), service 2 (sound
`{2,0..2}`), service 3 (alarm `{3,0..3}`: report/getSeed/arm/setConfig), service 4 (device/DFU
`{4,0..10}`) and `touchTest {0xF2,0}`. Return codes `ret_ok 0 / ret_fail 1 / ret_denied 2 /
ret_unimplemented 3 / ret_unnecessary 4`. All consistent with commands.md.

> Nuance: the app does **not** define service 0 constants for `getSerial/getSeed/resetPassword`
> `{0,5/0,6/0,7}`, which commands.md does list; those are on the firmware (nRF) side. To clear the
> password the app uses `setPassword {0,4}` with an empty payload (while authenticated), not the
> firmware's `{0,7}` challenge route.

## 5. `devicePass` handling

- `devicePass` is a field of the **cloud `SHUser`** (received in `login`/`signup`/`whoami` and stored
  locally). It's the **device's BLE pairing password** (≤32 bytes).
- Flow: after cloud authentication, the app starts the device service with `user.devicePass` and
  `user.deviceId`.
- In the BLE handshake, that string is sent **as is (UTF-8)** in `authenticate {0,3}` (no CRC) and,
  when pairing, in `setPassword {0,4}` (with CRC-CCITT-16 appended if firmware ≥ `V1_2_1` and
  password≠"").
- **This confirms the finding in `docs/api/endpoints.md`**: the official cloud kept the BLE password
  per user. By recovering it from `whoami` (against your own `sh2-server`) a client can authenticate
  against the device without re-pairing. The app doesn't derive the password from anything local: it
  treats it as an opaque value from the cloud.
