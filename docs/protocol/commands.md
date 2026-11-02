# SmartHalo 2 — BLE command catalog

> From the official app (ids and payloads), `auth.c` on the nRF side and `smarthalo2-stm-firmware`
> (implementation of services 1–4).
> Format of each command: **`[service, command, ...args]`** (see `ble-link.md`).
> Reply: first byte = return code (`0=OK`), followed by data if any.

## Service 0 — AUTH (handled by the nRF52; see `ble-link.md` §5 and `pairing.md`)

| Cmd | Name | Args → Reply |
| --- | --- | --- |
| `0,0` | getVersions | → `[OK, fw(4), bl(4)]` |
| `0,1` | getPeriphPubKey | → `[OK, periphPubKey(64), seed(4)]` |
| `0,2` | setCentralPubKey | `centralPubKey(64)` → `[OK]` |
| `0,3` | authenticate | `password(≤32)` → `[OK]`/`[FAIL]` (encrypted) |
| `0,4` | setPassword | `password(0 | 32 | 32+crc16)` → `[OK]` (requires permission) |
| `0,5` | getSerial | → device serial |
| `0,6` | getSeed | → `[OK, seed(4)]` |
| `0,7` | resetPassword | `challenge(32)` → `[OK]`/`[FAIL]` (see `pairing.md`) |

> `service 0xF` (`15`) exists as a **test/factory** route (`getSeed`=`15,0`, `enterFactory`=`15,1`);
> not needed for normal use.

## Service 1 — UI / OLED display + LED ring (STM32)

| Cmd | Name | Known payload |
| --- | --- | --- |
| `1,0` | logo | `cmd_logo` |
| `1,1` | nav | navigation glyph: `[1,1, c(3), stepType(0 destination, 8 U-turn), progress] + D(4) + text` |
| `1,2` | navReroute | |
| `1,3` | navOff | |
| **`1,4`** | **frontlight (ring)** | `[1,4, on?1:0, external?1:0]` |
| `1,5` / `1,6` | progress / progressOff | |
| `1,7` / `1,8` | notif / notif_off | `[1,7, c(3), c2(3), fadeIn(2), on(2), fadeOut(2), off(2), repeat, type] + text` / `[1,8]` (details below) |
| `1,9` / `1,10` | hb / hbOff | heartbeat/animation |
| `1,11` / `1,12` | compass / compassOff | |
| `1,13` | disconnect | |
| `1,14` | animOff | turn off the current animation |
| `1,15` | setBrightness | global brightness |
| **`1,16`** | **frontlightSettings** | `[1,16, lightMode(0=normal,1=blink), brightness, blinkingLocked?1:0, silenceRocker?1:0]` |
| `1,17` | navAngle (quick) | `[1,17, c(3), ang(2), progress\|sameTurn<<7, nc(3), nAng(2), nProgress] + D(4) + ND(4) + text` (the old 8-byte format makes the SH2 read past the payload) |
| `1,18` / `1,19` | speedometer / off | |
| `1,20` | roundabout | `[1,20, exitNow, style, 43 FF FF, FD ED FF, exits(int16 ×≤10)]` |
| `1,21` | lowBat | |
| `1,22`–`1,24` | nav_pointer / off / standby | pointer `[1,22, c(3), ang(2)] + D(4) + text`; off `[1,23]`; standby ("Ride to calibrate") `[1,24, c(3)] + D(4) + text` |
| `1,25` | demo | |
| `1,26` | speedometer_intro | |
| `1,27` | fitness_intro | |
| `1,28` / `1,29` | clock / clock_off | |
| `1,30` | front_external_toggle | |
| `1,31` | show_state_of_charger | |
| `1,32` | turn_by_turn_intro | `[1,32, mode(2), title… 0]` (title ≤ 29: the firmware copies it into 30 bytes unchecked) |
| `1,33` | pointer_with_intro | |
| `1,34` | roundabout_oled | `[1,34] + D(4) + text` |
| `1,35` | carousel | `[1,35, card, mask uint32 LE, payload…]`: header only = changes the mask; with payload = content of that card (the ring asks for it with UP `[5, card]` every second). Cards: 0 navigation, 1 goal, 2 distance, 3 time, 4 speed, 5 calories, 6 clock, 7 average speed, 8 CO₂, 9 battery (`RideTask.c` `updateCarouselMetricData`) |
| `1,36` | carousel_position | `[1,36, pos]`, or `[1,36, pos, mask lo, mask hi, 0, 0]` to change the mask too |
| `1,37` | touch_onboarding | |

Color = 3 HSV bytes `[h, s, v]`, 0–255 (the official app calls the third one `lightness`, but the
firmware treats it as value: `HsvToRgb`, `AnimationsLibrary.c`).

Navigation fields (details and sequences in [`navigation.md`](navigation.md)):
- `D(4)` distance: 4 bytes big-endian; **bit 31 = imperial** (`+0x80` in the high byte). Metric in
  meters, imperial in feet; the ring switches to miles on its own.
- `ang(2)`: signed degrees, int16 big-endian; 0 = straight, + = right.
- text: ISO-8859-1 terminated by `0`, total payload ≤ 80 bytes; the firmware stores 30 bytes.
- `1,9`/`1,10` (heartbeat), `1,11`/`1,12` (compass) and `1,33` (pointer with intro) **have no
  handler** in the SH2's STM firmware.

Notification `1,7` (`RideTask.c`, `notify` / `showNotification`):
- The firmware only uses `c`, `repeat`, `type` and `text`; it ignores `c2` and the four timings.
- Types with an icon: 0 call, 1 message, 32 storm, 64 horn, 65 clock, 66 home, 67 work,
  68 stop navigation, 69 error. Others: text only.
- With 15 payload bytes or fewer it doesn't use the display, only the ring.
- Duration: ring `(1 + repeat) × 500 + 700` ms; display `700 + 500 × repeat` ms. That value is a
  `uint16_t`: with `repeat` ≥ 130 it overflows.
- For twice that time, the ring doesn't show navigation; `1,8` releases it earlier.
- `1,8` doesn't clear the image on the display, and a new notification replaces the previous one.
- The firmware copies the text into 30 bytes without checking the length: 29 characters + NUL at most.

## Service 2 — Sound (STM32, piezo)

| Cmd | Name |
| --- | --- |
| `2,0` | play — `[2,0, volume ≤ 100, repeat, (freq Hz(2) ms(2))…]` |
| `2,1` | stop |
| `2,2` | touch_sounds | `[2,2, volume ≤ 100, on]` (the firmware fails with fewer bytes) |

## Service 3 — Alarm / system (STM32)

| Cmd | Name | Known payload |
| --- | --- | --- |
| `3,0` | report (getAlarmReport) | → `AlarmReport` |
| `3,1` | getSeed (alarm) | → seed |
| `3,2` | arm / set_alarm_state | `[3,2, seed(4), state]`: only changes the flag in RAM; **the official app never uses it** |
| **`3,3`** | **setConfig (configureAlarm)** | `[3,3, seed(4), tapCode, tapLength, armed, vigilant]` — this is how the official app arms and disarms. It's stored in flash; with `armed` the ring arms itself when **no phone is connected** and it isn't charging, and disarms on reconnection (`AlarmTask.c`). An optional 9th byte `allowStandby` (the official app **never** sends it) enables the "Manual Alarm": with a phone connected, the tap code turns off the Halo's BLE and arms it (`StandbyArmed`); it isn't restored from flash at boot |

## Service 4 — Device / DFU (STM32 + bootloader)

| Cmd | Name |
| --- | --- |
| `4,0` | enterBootloader |
| `4,1` | getState | `[OK, battery %, charging, 0, 0, light ready, light on, temperature int8 °C, plugged in, 0]`. Also UP `[4, battery, temp, plugged in]` every ~60 s |
| `4,2` | setName |
| `4,3` | compassCalibrate |
| `4,4` | shutdown |
| `4,5` | getSerial |
| `4,6` | localization |
| `4,7`/`4,8`/`4,9` | stmDfuCrc / stmDfuData / stmDfuInstall |
| `4,10` | forceInstallGolden |

## Experimental services

- `0xF2` (`-14`): `touchTest` = `0xF2,0`.
- `0xF8` (`-8`): experimental — `nav_destination_angle`(13), `show_oled`(21), `stop_oled`(22),
  `oled_contrast`(23), `oled_brightness`(24), `touch_calibration`(25), `swipe_calibration`(26).

## Basic use without the cloud

1. Handshake + authenticate.
2. **Light**: `ui_frontLight` → `[1,4,1,0]` (on) / `[1,4,0,0]` (off); brightness/blinking with
   `[1,16,...]`.
3. **Alarm**: `getAlarmReport` `[3,0]` (the counter resets to 0 on every read); turn on/off with
   `configureAlarm` `[3,3,...]` on every connection and every change, as the official app does.
4. `getVersions` `[0,0]` and `getSerial` `[0,5]` as sanity checks in cleartext/encrypted.
