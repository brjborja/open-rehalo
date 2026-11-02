// Real BLE backend — BlueZ via D-Bus (node-ble), no root. Reuses the existing
// DbusTransport and find-salt from clients/linux (read-only). Everything is lazily
// loaded and guarded: if there is no adapter / no node-ble / no firmware salt, the
// methods fail with a clear message instead of taking the app down, so mock mode is
// never affected.
//
// The transport and salt logic are the ones from clients/linux; this backend only adds
// a scanner and wires them into the shared backend contract.
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

export async function createBleBackend({ srcBase, core, log = () => {} }) {
  const url = (rel) => pathToFileURL(join(srcBase, rel)).href;

  // Firmware salt (needed only for the recover/reset-challenge flow).
  let salt = null;
  try {
    const { readSalt } = await import(url('clients/linux/src/find-salt.mjs'));
    salt = readSalt();
  } catch (e) {
    log(`Could not read the firmware salt: ${e.message} — BLE recovery stays disabled until it is available (set SH2_FIRMWARE_SRC).`, 'warn');
  }

  let bluetooth = null, destroy = null, adapter = null, transport = null;

  async function ensureAdapter() {
    if (adapter) return adapter;
    let nb;
    try { nb = await import('node-ble'); }
    catch (e) { throw new Error(`node-ble not available (${e.message}). Did you run npm install in clients/desktop?`); }
    const bt = nb.createBluetooth();
    bluetooth = bt.bluetooth; destroy = bt.destroy;
    adapter = await bluetooth.defaultAdapter();   // throws if no BlueZ adapter
    if (!(await adapter.isPowered())) await adapter.setPowered(true);
    return adapter;
  }

  return {
    mode: 'ble',
    getSalt() {
      if (!salt) throw new Error('firmware salt not available (set SH2_FIRMWARE_SRC to the path of auth.c)');
      return salt;
    },

    async scan(durationMs, onDevice) {
      const a = await ensureAdapter();
      if (!(await a.isDiscovering())) await a.startDiscovery();
      const end = Date.now() + (durationMs || 15000);
      const seen = new Map();
      const out = [];
      while (Date.now() < end) {
        for (const mac of await a.devices()) {
          if (seen.has(mac)) continue;
          try {
            const d = await a.getDevice(mac);
            let name = ''; try { name = await d.getName(); } catch {}
            seen.set(mac, name);
            const entry = { id: mac, name: name || '(unnamed)', address: mac, isHalo: /halo/i.test(name) };
            out.push(entry);
            if (onDevice) onDevice(entry);
          } catch {}
        }
        await new Promise((r) => setTimeout(r, 1500));
      }
      await a.stopDiscovery().catch(() => {});
      // SmartHalo candidates first
      out.sort((x, y) => (y.isHalo === true) - (x.isHalo === true));
      return out;
    },

    async createTransport(id) {
      const { DbusTransport } = await import(url('clients/linux/src/dbus-transport.mjs'));
      transport = new DbusTransport();
      await transport.connect(id);
      return transport;
    },

    async teardown() {
      try { if (transport) await transport.disconnect(); } catch {}
      try { if (destroy) destroy(); } catch {}
      transport = null; adapter = null; bluetooth = null; destroy = null;
    },
  };
}
