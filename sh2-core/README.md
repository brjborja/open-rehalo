# sh2-core

Transport-agnostic BLE protocol core for the SmartHalo 2. ESM JavaScript with
**zero dependencies** (uses `node:crypto` and the `node --test` runner). Can be ported to TS once
a toolchain is added. Cross-platform through different *transports* (node-ble on Linux, Web Bluetooth, etc.).

## Modules (`src/`)

- `crypto.mjs` — ECDH P-256, AES-128-CBC (PKCS#7), link key derivation and the password reset
  challenge. We act as the "central" (like the official app).
- `frame.mjs` — "bslink" framing: service UUIDs, splitting into 20-byte MTU chunks, CTRL `[len,crypted]`.
- `commands.mjs` — payload builders per service (auth, light, alarm, sound, device).
- `session.mjs` — `Session(transport)`: `open()`, `handshake(password)`, `transceive(data)`,
  `onNotification`. Drives the ECDH→AES handshake and the request/response cycle.
- `recovery.mjs` — recovery of your own device when its pairing or PIN is unknown.
- `index.mjs` — public API.

## Transport

`Session` talks to a `Transport` object:

```js
interface Transport {
  writeNoResponse(uuid: string, data: Buffer): Promise<void>;
  subscribe(uuid: string, cb: (data: Buffer) => void): Promise<void>; // enables notify (CCCD)
}
```

The Linux transport uses **node-ble** over D-Bus (BlueZ); see `clients/linux/src/dbus-transport.mjs`.
It needs `npm i` in that folder and a BLE adapter. The `test/session.test.mjs` test includes a
`MockDevice` that acts as a SmartHalo 2 in software.

## Usage

```js
import { Session, commands } from 'sh2-core';
const s = new Session(transport);
await s.open();
await s.handshake(password);                 // '' if the device is not paired
await s.transceive(commands.frontLight(true)); // turn the light on
```

## Tests

```
npm test   # = node --test  (crypto, frame, commands, handshake e2e, recovery)
```

## Validation status

**Verified in software**: mutual ECDH, AES round-trip, framing, e2e handshake (MockDevice).
