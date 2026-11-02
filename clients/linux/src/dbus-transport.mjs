// BLE transport for Linux via BlueZ/D-Bus (node-ble). Implements the interface that
// sh2-core/Session expects: writeNoResponse(uuid,data) + subscribe(uuid,cb). No root needed
// (it goes through bluetoothd).
import { createBluetooth } from 'node-ble';
import { UUID } from 'sh2-core';

export class DbusTransport {
  constructor() { this._chars = new Map(); }

  /** Connects to the device by MAC and resolves the service and characteristics. */
  async connect(mac, { timeoutMs = 20000 } = {}) {
    const { bluetooth, destroy } = createBluetooth();
    this._destroy = destroy;
    const adapter = await bluetooth.defaultAdapter();
    if (!(await adapter.isDiscovering())) await adapter.startDiscovery();
    this.device = await adapter.waitDevice(mac.toUpperCase(), timeoutMs);
    await this.device.connect();
    this.gatt = await this.device.gatt();
    this.service = await this.gatt.getPrimaryService(UUID.service);
    return this;
  }

  async _char(uuid) {
    if (!this._chars.has(uuid)) this._chars.set(uuid, await this.service.getCharacteristic(uuid));
    return this._chars.get(uuid);
  }

  async writeNoResponse(uuid, data) {
    const c = await this._char(uuid);
    // NOTE: the bslink chars are Write-WITH-Response in the firmware (bleapp.c:700 sets
    // char_props.write, NOT write_wo_resp). With type:'command' (no response), BlueZ/node-ble
    // drops the write silently and the ring never gets the command. Use type:'request'.
    // Validated against a real SmartHalo 2 (2026-10-27): getSeed only answers with 'request'.
    await c.writeValue(Buffer.from(data), { type: 'request' }); // write-WITH-response
  }

  async subscribe(uuid, cb) {
    const c = await this._char(uuid);
    await c.startNotifications();
    c.on('valuechanged', (buf) => cb(Buffer.from(buf)));
  }

  async disconnect() {
    try { if (this.device) await this.device.disconnect(); } catch {}
    try { if (this._destroy) this._destroy(); } catch {}
  }
}
