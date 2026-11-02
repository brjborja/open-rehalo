# sh2-server

Open-source reimplementation of the SmartHalo 2 cloud backend, for **self-hosting**.
Node ESM, **zero dependencies** (`node:http`, `node:crypto`). Runs in Docker or anywhere with Node.

## Getting started

```bash
npm start                       # listens on :8730
PORT=8730 SH2_DATA_DIR=./data SH2_JWT_SECRET=... npm start
```

Data lives in `SH2_DATA_DIR` (default `./data`): `users.json` + `jwt.secret` (auto-generated).

## Modules

- `jwt.mjs` — JWT HS256 (sign/verify). `auth.mjs` — scrypt password hashing.
- `store.mjs` — `UserStore` in a JSON file (can be migrated to SQLite/Postgres).
- `server.mjs` — `createApp({store,secret})`: router + handlers. `index.mjs` — startup.

## Endpoints

See [`../docs/api/endpoints.md`](../docs/api/endpoints.md). Auth + User + **complete, persistent
Rides + Favourites + Configs** (shapes aligned with the app's models, see below).

## Tests

```
npm test   # node --test: 16 e2e tests over real HTTP (auth/user + rides/favourites/configs)
```

## Status

- Done: auth (signup/login/refresh/checkEmail) + user (whoami/update); rides v1/v2
  (list/sync/get/patch/delete), favourites (list/create/delete) and configs (get/put/delete),
  real and persistent in `UserStore` (`rides`/`favourites`/`configs` arrays per user).
- Shapes: `SHPastRide` (v1, camelCase), `CloudRide` (v2, snake via `@SerializedName`),
  `RideMarker`/`CloudMarker`/`UserFavourite`.
- Acknowledgement stubs: `v2/dfu` (no update), `device_connections`, `activities`.

## Aligned with the official app v1.18.0
- The **`x-consumer-token`** header is optional. Set `SH2_CONSUMER_TOKEN` to require it on
  login/signup/refresh and on all v2 routes. It has no default; when unset, the header is not required.
- `users/update` = **PUT**; `checkEmail`/`forgot` respond with a **scalar** (`true`/`false`/`ok`);
  `refresh_tokens` uses a `{data:{…}}`→`{data:[{…}]}` envelope.
- v2 endpoints (persistent stubs where applicable): configs, favourites, rides v2, `v2/dfu`,
  `device_connections`, `activities`. Details in `../docs/api/official-app-api-notes.md`.
