# SmartHalo 2 — Protocol

Protocol documentation for the SmartHalo 2, written to support an open-source alternative. It comes
from cross-reading the **official firmware** (published after the company closed) and reverse
engineering the **official Android app**. The firmware and the app are consistent with each other.

## Index

- [`ble-link.md`](ble-link.md) — the "bslink" BLE link layer: GATT, framing, encryption and handshake.
- [`commands.md`](commands.md) — command catalog by service (auth, UI/display, sound, alarm,
  device/DFU).
- [`pairing.md`](pairing.md) — pairing password and recovery of your own device.
- [`navigation.md`](navigation.md) — the official app's GPX navigation: turns, rider heading, ring
  commands.

## Device architecture (summary)

- **Two chips**: nRF52832 (BLE, nRF5 SDK 16) ↔ STM32L4 (OLED display, LED ring, sound, alarm/ride
  logic), connected over **UART**.
- The nRF handles service 0 (auth) and forwards every other service to the STM32 over UART.
- 128-bit vendor GATT with two channels (down/up), each with 1 ctrl + 4 payload characteristics
  (MTU 20).
- Link encrypted with **AES-128-CBC** after a **P-256 ECDH handshake**; commands are protected by a
  **device password** of up to 32 bytes.

## Reference sources

| What | Where |
| --- | --- |
| nRF firmware (BLE/auth/bslink) | `smarthalo-community/smarthalo-firmware`, nRF firmware source (`Code/Firmware/shapp/src/`) |
| STM32 firmware (light/alarm/display) | `smarthalo-community/smarthalo-firmware`, STM firmware source (`Src/`) |
| Android BLE SDK | The official Android app |
| Cloud API docs and stub | `aolde/smarthalo-api` |

## Confidence by section

- **Link, framing, UUIDs, handshake**: high (firmware and app match).
- **Command IDs**: high (the official app's command table is consistent with the firmware dispatch).
- **Payloads of each command**: partial. Light, alarm and navigation are confirmed; the rest are
  completed by reading the STM32 controllers.
- **Pairing/recovery**: the mechanism is clear from the firmware source.
