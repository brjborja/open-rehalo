# SmartHalo 2 — Cloud API (reimplementation)

> Implemented in `sh2-server/`. The API comes from `aolde/smarthalo-api` (definition and stub) and from
> reverse engineering the official app v1.18.0. The authoritative notes are in
> [`official-app-api-notes.md`](official-app-api-notes.md).

The official host was `api.smarthalo.bike`. `sh2-server` keeps the official headers and shapes:
**`x-consumer-token`** is checked on login/signup/refresh and on v2 endpoints when `SH2_CONSUMER_TOKEN`
is set, and isn't required otherwise.

## Endpoints

### Auth (no `x-access-token`)
| Method | Path | Body | Response |
| --- | --- | --- | --- |
| POST | `/auth/local/checkEmail` | `{email}` | raw scalar `true` / `false` |
| POST | `/auth/local/signup` | `{email,password,firstName,lastName,dateOfBirth,language}` | `{access_jwt,refresh_jwt,user}` |
| POST | `/auth/local/login` | `{email,password}` | `{access_jwt,refresh_jwt,user}` |
| POST | `/auth/local/refresh_tokens` | `{data:{refresh_jwt}}` | `{data:[{access_jwt,refresh_jwt}]}` |
| POST | `/auth/forgot` | `{email}` | raw scalar `ok` *(stub)* |

### User (header `x-access-token: <access_jwt>`)
| Method | Path | | |
| --- | --- | --- | --- |
| GET | `/api/v1/users/whoami` | → `SHUser` | |
| PUT | `/api/v1/users/update` | `{user:{...}}` → `ok` | |
| POST | `/api/v1/users/sendConfirm` | → `ok` *(stub)* | |

### Rides (header `x-access-token`)
`GET /api/v1/users/rides` · `POST /api/v1/users/rides/sync` · `GET|PATCH /v2/users/me/rides/:id` ·
`DELETE /api/v2/rides/:id`. Stored per user.

### Configs and favourites (header `x-access-token`)
`GET|PUT|DELETE /api/v2/users/:userId/configs` · `GET|POST|DELETE /api/v2/users/:userId/favourites`.
Stored per user.

### Acknowledged only
`GET /v2/dfu` → `{data:[]}` (no update available) · `POST /api/v2/device_connections` ·
`POST /v2/activities`.

## SHUser model (relevant fields)

`email, firstName, lastName, key` (required); `id, dateOfBirth, deviceId, deviceVersion, devicePass,
picture, language, gender, height/weight(+Metric), isConfirmed, created_at`.

> **Key finding**: `devicePass` — the official backend stored **the device's BLE pairing password per
> user**. `sh2-server` stores it through `/api/v1/users/update` and returns it in `whoami`, so a client
> can recover the device password from your own server (see `docs/protocol/pairing.md`).
