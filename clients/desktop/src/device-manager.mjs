// SmartHalo 2 desktop — transport-agnostic device manager.
//
// Owns the logical Session (from sh2-core) and the recovery flow, and drives it
// over whichever Transport a *backend* provides. Two backends implement the exact
// same contract: `mock` (emulator Sh2Device, no hardware) and `ble` (BlueZ/D-Bus).
// Everything above the backend is identical for both — that's the whole point.
//
// Public methods never throw: they return { ok, ... } and report problems via the
// `log` event, so the UI (and the test harness) can stay simple.
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createMockBackend } from './backends/mock-backend.mjs';
import { createBleBackend } from './backends/ble-backend.mjs';

export class DeviceManager {
  /**
   * @param {{srcBase:string, emit?:(name:string,payload:any)=>void}} o
   *   srcBase: absolute dir that contains sh2-core/, emulator/, clients/ (repo root in
   *   dev, process.resourcesPath when packaged). Used to resolve the read-only libs.
   */
  constructor({ srcBase, emit = () => {} }) {
    this.srcBase = srcBase;
    this.emit = emit;
    this.core = null;                // { Session, recovery, commands, UUID }
    this.backend = null;
    this.mode = 'mock';
    this.session = null;
    this.transport = null;
    this.connectedId = null;
    this.connectedName = null;
    this.authed = false;             // handshake/recover succeeded -> controls allowed
    this.lastPassword = null;        // last 32-char device password we set/know
    this.light = { on: false, brightness: 80 };
  }

  _url(rel) { return pathToFileURL(join(this.srcBase, rel)).href; }

  async _loadCore() {
    if (this.core) return this.core;
    const [session, recovery, commands, frame] = await Promise.all([
      import(this._url('sh2-core/src/session.mjs')),
      import(this._url('sh2-core/src/recovery.mjs')),
      import(this._url('sh2-core/src/commands.mjs')),
      import(this._url('sh2-core/src/frame.mjs')),
    ]);
    this.core = { Session: session.Session, recovery, commands, UUID: frame.UUID };
    return this.core;
  }

  log(msg, level = 'info') { this.emit('log', { msg, level, t: Date.now() }); }
  pushStatus() { this.emit('status', this.snapshot()); }

  snapshot() {
    return {
      mode: this.mode,
      connected: !!this.session,
      connectedId: this.connectedId,
      connectedName: this.connectedName,
      authed: this.authed,
      light: { ...this.light },
      hasPassword: !!this.lastPassword,
      password: this.lastPassword,
    };
  }

  async setMode(mode) {
    if (mode !== 'mock' && mode !== 'ble') return { ok: false, error: `invalid mode: ${mode}` };
    await this.disconnect();
    if (this.backend) { try { await this.backend.teardown(); } catch {} this.backend = null; }
    this.mode = mode;
    this.log(mode === 'mock'
      ? 'EMULATOR (mock) mode: no hardware, everything runs against Sh2Device.'
      : 'Real BLE mode (BlueZ/D-Bus).');
    this.pushStatus();
    return { ok: true, mode };
  }

  async _ensureBackend() {
    if (this.backend) return this.backend;
    const core = await this._loadCore();
    const common = { srcBase: this.srcBase, core, log: (m, l) => this.log(m, l) };
    this.backend = this.mode === 'mock'
      ? await createMockBackend(common)
      : await createBleBackend(common);
    return this.backend;
  }

  async scan(durationMs = 8000) {
    try {
      const backend = await this._ensureBackend();
      this.log(`Scanning (${this.mode})…`);
      const list = await backend.scan(durationMs, (d) => this.emit('device', d));
      this.log(`Scan finished: ${list.length} device(s).`);
      return { ok: true, devices: list };
    } catch (e) {
      this.log(`Scan failed: ${e.message}`, 'error');
      return { ok: false, error: e.message, devices: [] };
    }
  }

  async connect(id, name) {
    try {
      const backend = await this._ensureBackend();
      await this.disconnect();
      this.log(`Connecting to ${name || id}…`);
      this.transport = await backend.createTransport(id);
      this.session = new this.core.Session(this.transport);
      await this.session.open();
      this.connectedId = id;
      this.connectedName = name || id;
      this.authed = false;
      this.log(`Connected to ${this.connectedName}. Pairing or authentication is still needed.`);
      this.pushStatus();
      return { ok: true, name: this.connectedName };
    } catch (e) {
      this.log(`Connection failed: ${e.message}`, 'error');
      await this.disconnect();
      return { ok: false, error: e.message };
    }
  }

  _needSession() { if (!this.session) throw new Error('no device connected'); }

  async authenticate(password) {
    try {
      this._needSession();
      if (!password) throw new Error('enter the 32-character device password');
      this.log('Handshake + authenticate with the given password…');
      await this.session.handshake(password);
      this.authed = true;
      this.lastPassword = password;
      this.log('Authenticated ✅ (controls enabled).');
      this.pushStatus();
      return { ok: true };
    } catch (e) {
      this.authed = false;
      this.log(`Authentication failed: ${e.message}`, 'error');
      this.pushStatus();
      return { ok: false, error: e.message };
    }
  }

  async recover(newPassword) {
    try {
      this._needSession();
      const backend = await this._ensureBackend();
      const salt = backend.getSalt();
      this.log('Recovery: getSeed → resetPassword(SHA256(seed‖salt)) → handshake("") → setPassword(new)…');
      const pw = await this.core.recovery.recoverAccess(this.session, salt, newPassword || undefined);
      this.authed = true;
      this.lastPassword = pw;
      this.log('Re-paired ✅. NEW password generated (save it, this is the only copy).');
      this.pushStatus();
      return { ok: true, password: pw };
    } catch (e) {
      this.log(`Recovery failed: ${e.message}`, 'error');
      this.pushStatus();
      return { ok: false, error: e.message };
    }
  }

  async _send(appData, label) {
    this._needSession();
    if (!this.authed) throw new Error('authenticate or recover before sending commands');
    const r = await this.session.transceive(appData);
    const ret = r[0];
    const ok = ret === this.core.commands.RET.OK;
    this.log(`${label} → ${ok ? 'OK ✅' : `RET=${ret}`}`, ok ? 'info' : 'warn');
    return { ok, ret, raw: Buffer.from(r).toString('hex') };
  }

  async frontLight(on) {
    try {
      const res = await this._send(this.core.commands.frontLight(!!on), `Front light ${on ? 'ON' : 'OFF'}`);
      if (res.ok) { this.light.on = !!on; this.pushStatus(); }
      return res;
    } catch (e) { this.log(`Light failed: ${e.message}`, 'error'); return { ok: false, error: e.message }; }
  }

  async setBrightness(v) {
    try {
      const val = Math.max(0, Math.min(255, Number(v) | 0));
      const res = await this._send(this.core.commands.setBrightness(val), `Brightness ${val}`);
      if (res.ok) { this.light.brightness = val; this.pushStatus(); }
      return res;
    } catch (e) { this.log(`Brightness failed: ${e.message}`, 'error'); return { ok: false, error: e.message }; }
  }

  async alarm(action) {
    try {
      const c = this.core.commands;
      if (action === 'arm') return await this._send(c.alarmSetState(0, 1), 'Alarm ARM');
      if (action === 'disarm') return await this._send(c.alarmSetState(0, 0), 'Alarm DISARM');
      if (action === 'report') {
        const res = await this._send(c.alarmReport(), 'Alarm REPORT');
        return res;
      }
      throw new Error(`unknown alarm action: ${action}`);
    } catch (e) { this.log(`Alarm failed: ${e.message}`, 'error'); return { ok: false, error: e.message }; }
  }

  async deviceInfo() {
    try {
      this._needSession();
      if (!this.authed) throw new Error('authenticate or recover first');
      const c = this.core.commands;
      const versions = await this.session.transceive(c.getVersions());
      const state = await this.session.transceive(c.getState());
      const info = {
        mode: this.mode,
        name: this.connectedName,
        authed: this.authed,
        password: this.lastPassword,
        getVersions: { ret: versions[0], raw: Buffer.from(versions).toString('hex') },
        getState: { ret: state[0], raw: Buffer.from(state).toString('hex') },
      };
      this.log('Device info requested (getVersions / getState).');
      return { ok: true, info };
    } catch (e) { this.log(`Info failed: ${e.message}`, 'error'); return { ok: false, error: e.message }; }
  }

  async disconnect() {
    try {
      if (this.transport && typeof this.transport.disconnect === 'function') {
        await this.transport.disconnect();
      }
    } catch {}
    const was = !!this.session;
    this.session = null;
    this.transport = null;
    this.connectedId = null;
    this.connectedName = null;
    this.authed = false;
    this.light.on = false;
    if (was) { this.log('Disconnected.'); this.pushStatus(); }
    return { ok: true };
  }
}
