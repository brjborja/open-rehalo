# rehalo — native iOS client for the SmartHalo 2 (SwiftUI + CoreBluetooth)

An iOS app to control your own SmartHalo 2 now that the company has closed. No account is needed: the
ring is controlled over Bluetooth LE directly between your iPhone and the device. An optional
self-hosted server adds accounts and ride history. Map search uses Apple Maps, and optional rain alerts
use Open-Meteo. It is the iOS counterpart to `clients/linux` and `clients/desktop`, built on the same
protocol described in `docs/protocol/` and ported from `sh2-core`.

> iOS has no Web Bluetooth, so a web client can't talk to the device on iPhone — this native app
> is the iOS path.

## What it does (the app is called **rehalo** on the home screen)

- **Three tabs** — **Map · Routes · Halo** — dark Halo theme, a global connection chip and
  **auto-connect** to "my Halo" (remembered and reconnected on launch / after a drop). English +
  Spanish (`Resources/Localizable.xcstrings`), km / mi setting.
- **Map:** pick a route and **NAVIGATE** — full-screen guidance with turn banner, follow camera,
  speed / remaining / % and turn-by-turn guidance on the ring; keeps going in the background and
  through Halo drops; ride summary at the end. **Destinations**: search a place or touch and hold the map, pick a
  profile (City, Road or Trails), then NAVIGATE on Apple's route and its turns (street names on the
  ring) or **Compass** (the ring points straight at it). Far from a route's start, it offers to lead
  you there first. The screen shows the same turns and off-route state as the ring.
- **Routes library** (SwiftData): import GPX from Files or **Share › rehalo / Open in…** from
  Wikiloc, Komoot, Strava, Mail, AirDrop; route detail with map, stats and elevation profile; a
  bundled demo route.
- **Live Activity / Dynamic Island** while navigating: next turn + distance + %, expanded and Lock
  Screen views with speed, remaining distance, progress and a **front-light button** (an App
  Intent that runs in the app and uses the open BLE session).
- **Halo tab:** battery, light (on/off, brightness, blink) and alarm cards, alarm notification when
  the bike moves (needs a live BLE link), Settings (my Halo, alarm sensitivity, account, units,
  Advanced: firmware info, clock/compass, sound & touch, live log, ride recording for bug reports,
  demo mode, shut down).
- **Call alerts**: the ring pulses for an incoming call and a short tap silences it.
- **Rain alerts**: optional and off by default; the ring warns of rain during a ride.
- **Onboarding** (welcome → pair → permissions → optional account) and a **recovery wizard** that
  re-takes ownership of your own ring when its password is unknown (firmware reset challenge, new
  32-byte password stored in the Keychain).
- **Demo mode** ("Try without a Halo"): a simulated ring and rider cover every screen.

## Layout

```
clients/ios/
├── project.yml                   # XcodeGen: app target SmartHalo2 + HaloLiveActivity extension
├── SH2Protocol/                  # SPM package — PORTABLE layers, `swift test`:
│                                 #   SH2Nav: commands + ride logic (`RideEngine`), also builds on Linux
│                                 #   SH2Protocol: session + crypto (re-exports SH2Nav), Apple only
└── Sources/
    ├── Shared/                   # compiled into app AND extension: HaloNavAttributes, light intent
    ├── HaloLiveActivity/         # WidgetKit extension: navigation Live Activity only (+ ES/EN strings)
    └── SmartHalo2App/            # the iOS app (SwiftUI + CoreBluetooth + MapKit + SwiftData)
        ├── BLE/  Keychain/  Demo/  Server/
        ├── Model/                # HaloConnection, DeviceController, GuidanceController,
        │                         # LiveActivityManager, RouteLibrary, UnitFormat, …
        ├── Resources/            # Localizable.xcstrings, DemoRoute.gpx
        └── UI/                   # Shell, Map, Routes, Halo, Settings, Onboarding, Recovery,
                                  # Components, Theme
```

The Live Activity extension has its own bundle id (`com.sh2.smarthalo2.LiveActivity`); when you
sign with a free Apple ID it uses one more App ID.

## Crypto approach (and the API caveats to watch)

- **ECDH**: CryptoKit `P256.KeyAgreement`. Peer public key is rebuilt from the 64-byte `X‖Y` via
  `x963Representation` = `0x04 ‖ X ‖ Y`; our own wire public key is
  `publicKey.x963Representation` with the leading `0x04` dropped (64 B).
- **Shared secret**: the **raw 32-byte X coordinate** of the agreement (NOT HKDF-derived). We read
  it from `SharedSecret.withUnsafeBytes`. CryptoKit normally pushes you toward
  `hkdfDerivedSymmetricKey(...)` — do **not** use that here; the firmware uses the bare agreement.
  Then bytes `[16..20)` of that secret are overwritten with the device's 4-byte `seed`; AES key =
  `secret[0..16]`, IV = `secret[16..32]`.
- **AES-128-CBC/PKCS7**: CommonCrypto `CCCrypt` (CryptoKit has no AES-CBC). CBC is the default mode
  for the one-shot `CCCrypt` (no ECB option flag), and `kCCOptionPKCS7Padding` gives PKCS#7.
  `import CommonCrypto` works out of the box in SPM/Xcode on Apple platforms.
- **SHA-256**: CryptoKit `SHA256` — used for the reset challenge `SHA256(seed‖salt)`.

Every protocol file has comments mapping it back to the matching `sh2-core/src/*.mjs` source.

## Open in Xcode / run on an iPhone

Requires a Mac with Xcode 16+ (iOS 17+ target) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd clients/ios
brew install xcodegen          # if you don't have it
xcodegen generate              # creates SmartHalo2.xcodeproj
open SmartHalo2.xcodeproj
```

Then in Xcode:
1. Select the **SmartHalo2** target → **Signing & Capabilities** → pick your **Team**
   (or set `DEVELOPMENT_TEAM` in `project.yml` and re-run `xcodegen generate`).
2. Plug in your iPhone, select it as the run destination, and **Run**.
3. On first launch, grant the **Bluetooth** permission.
4. Follow the onboarding: the scan starts by itself (tap or charge the SmartHalo so it
   advertises); if the ring was paired with the original app, the recovery wizard claims it.

> CoreBluetooth needs a **real device** — the iOS Simulator has no Bluetooth. Demo mode works there.

## Run the protocol unit tests (on a Mac)

The protocol layer is a standalone Swift package so its logic is testable without the app:

```bash
cd clients/ios/SH2Protocol
swift test        # runs SH2ProtocolTests: ECDH round-trip, AES round-trip, framing encode/decode
```

## Notes, scope & known limitations

- **No account needed.** Controlling the ring needs no login. The self-hosted `sh2-server` is
  optional and adds accounts and ride history (`Server/SH2Server.swift`).
- **Scanning caveat.** Per `docs/protocol/ble-link.md` §1 some units advertise only the 16-bit
  `0x5348` ("SH") id, not the 128-bit service. The scanner filters by both; if your unit still
  never appears, set `scanByServiceOnly = false` in `BluetoothCentral.startScan()` to scan broadly
  and match by name.
- **`resetPassword` FAIL** means the salt/algorithm of your specific unit differs from the public
  firmware — the recovery stops and reports it (don't retry blindly). The salt comes from `auth.c`
  (`FirmwareConstants.swift`); same assumption as the Linux/desktop clients.
- **Alarm.** The app arms and disarms with `configureAlarm` `{3,3}`
  (`[3,3, seed(4), tapCode, tapLength, armed, vigilant]`), sent on every connection and every change,
  as the official app does. It never sends `{3,2}`. With the alarm on, the ring arms itself once no
  phone is connected, and disarms when one reconnects.
