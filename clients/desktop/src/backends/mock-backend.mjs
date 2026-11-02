// Mock backend — drives the whole app against the emulator's Sh2Device (no hardware).
// Implements the backend contract: scan(durationMs,onDevice) -> [{id,name,...}],
// createTransport(id) -> Transport, getSalt() -> Buffer, teardown().
//
// The emulator's bleTransport() returns a MockDevice that already implements the
// Transport interface (writeNoResponse/subscribe), so the Session code is unchanged.
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

export async function createMockBackend({ srcBase, core, log = () => {} }) {
  const url = (rel) => pathToFileURL(join(srcBase, rel)).href;
  const { Sh2Device, STANDBY } = await import(url('emulator/src/sh2-device.mjs'));

  // Salt for the reset-challenge: prefer the real firmware source (so the mock behaves
  // exactly like a real unit), fall back to a fixed demo salt when it isn't available
  // (e.g. inside a packaged AppImage without the firmware tree).
  let salt;
  try {
    const { readSalt } = await import(url('clients/linux/src/find-salt.mjs'));
    salt = readSalt();
    log('Salt read from the public firmware source (auth.c).');
  } catch {
    salt = Buffer.alloc(16, 0x5a);
    log('Firmware source not available; using a demo salt (0x5a×16) for the emulator.');
  }

  // A device that is already paired with an UNKNOWN old password and whose nRF is powered
  // (standby Off) so it is reachable over BLE — the realistic "I bought a bricked SH2" case.
  const dev = new Sh2Device({
    devicePass: 'OLD-UNKNOWN-PASSWORD-32-chars-xx',
    salt,
    standby: STANDBY.Off,
  });

  return {
    mode: 'mock',
    device: dev,
    getSalt: () => salt,

    async scan(durationMs, onDevice) {
      const adv = dev.scanBLE();
      const list = [];
      if (adv) {
        const d = { id: 'mock-0', name: adv.name, address: 'MO:CK:5A:5A:00:00', rssi: -42, isHalo: true };
        // small delay so the UI shows a real "scanning…" moment
        await new Promise((r) => setTimeout(r, Math.min(400, Math.max(0, durationMs | 0))));
        list.push(d);
        if (onDevice) onDevice(d);
      }
      return list;
    },

    async createTransport(/* id */) {
      // The emulator keeps cipher/authed across sessions on its nRF; clear them so a
      // fresh Session can perform a clean handshake (same reset run-recovery.mjs does).
      if (dev.nrf) { dev.nrf.cipher = undefined; dev.nrf.authed = false; }
      const transport = dev.bleTransport();
      // give it a no-op disconnect so the manager can call it uniformly
      if (typeof transport.disconnect !== 'function') transport.disconnect = async () => {};
      return transport;
    },

    async teardown() { /* nothing to release for the emulator */ },
  };
}
