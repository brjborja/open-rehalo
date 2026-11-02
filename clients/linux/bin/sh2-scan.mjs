#!/usr/bin/env node
// Scans BLE and lists SmartHalo candidates (by name). Prints the MAC to use with sh2-pair.
import { createBluetooth } from 'node-ble';

const SECS = Number(process.argv[2] || 20);
const { bluetooth, destroy } = createBluetooth();
const adapter = await bluetooth.defaultAdapter();
if (!(await adapter.isPowered())) await adapter.setPowered(true);
if (!(await adapter.isDiscovering())) await adapter.startDiscovery();
console.error(`Scanning ${SECS}s...  (wake or charge the SmartHalo)`);

const end = Date.now() + SECS * 1000;
const seen = new Map();
while (Date.now() < end) {
  for (const mac of await adapter.devices()) {
    if (seen.has(mac)) continue;
    try {
      const d = await adapter.getDevice(mac);
      let name = ''; try { name = await d.getName(); } catch {}
      seen.set(mac, name);
      const hit = /halo|smarthalo/i.test(name);
      console.log(`${hit ? '>>> ' : '    '}${mac}  ${name || '(unnamed)'}`);
    } catch {}
  }
  await new Promise((r) => setTimeout(r, 1500));
}
await adapter.stopDiscovery().catch(() => {});
destroy();
const halos = [...seen].filter(([, n]) => /halo|smarthalo/i.test(n));
if (halos.length) console.error(`\nSmartHalo(s): ${halos.map(([m]) => m).join(', ')}\n→ sh2-pair <MAC>`);
else console.error('\nNo SmartHalo found by name. If you can see it by MAC, try anyway: sh2-pair <MAC>');
process.exit(0);
