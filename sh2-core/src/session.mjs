// SmartHalo 2 — logical session over a connectable BLE Transport.
// Drives the handshake (ECDH->AES) + transceive with bslink framing.
// See docs/protocol/ble-link.md. The logic here is transport-agnostic; concrete Transports
// (node-ble, Web Bluetooth, bleak) are supplied by the caller.
import { UUID, encodeMessage, decodeReply } from './frame.mjs';
import { generateKeyPair, publicKeyXY, deriveSecret } from './crypto.mjs';
import * as cmd from './commands.mjs';

/**
 * @typedef {Object} Transport
 * @property {(uuid:string, data:Buffer)=>Promise<void>} writeNoResponse
 * @property {(uuid:string, cb:(data:Buffer)=>void)=>Promise<void>} subscribe
 */

export class Session {
  /** @param {Transport} transport */
  constructor(transport) {
    this.t = transport;
    this.cipher = undefined;            // {key, iv} once the handshake is done
    this._accum = [];                   // PAYLOAD chunks from the DOWN channel
    this._pending = null;               // {resolve,reject} of the transceive in progress
    this._upAccum = [];                 // chunks from the UP channel
    this.onNotification = null;         // cb(appData:Buffer) for UP notifications
  }

  async open() {
    for (const u of UUID.payload) await this.t.subscribe(u, (d) => this._accum.push(Buffer.from(d)));
    await this.t.subscribe(UUID.ctrl, (d) => this._onCtrl(Buffer.from(d)));
    for (const u of UUID.upPayload) await this.t.subscribe(u, (d) => this._upAccum.push(Buffer.from(d)));
    await this.t.subscribe(UUID.upCtrl, (d) => this._onUpCtrl(Buffer.from(d)));
  }

  _onCtrl(ctrl) {
    if (!this._pending) return;
    const p = this._pending; this._pending = null;
    try {
      const reply = decodeReply(ctrl, Buffer.concat(this._accum), this.cipher);
      this._accum = [];
      p.resolve(reply);
    } catch (e) { this._accum = []; p.reject(e); }
  }

  _onUpCtrl(ctrl) {
    try {
      const data = decodeReply(ctrl, Buffer.concat(this._upAccum), this.cipher);
      this._upAccum = [];
      if (this.onNotification) this.onNotification(data);
    } catch { this._upAccum = []; }
  }

  /** Sends an app payload and waits for the reply. `crypted` defaults to whether a cipher exists. */
  async transceive(appData, { crypted } = {}) {
    if (this._pending) throw new Error('a transceive is already in progress');
    const useCipher = (crypted ?? !!this.cipher) ? this.cipher : undefined;
    const { chunks, ctrl } = encodeMessage(appData, useCipher);
    const done = new Promise((resolve, reject) => { this._pending = { resolve, reject }; });
    for (let i = 0; i < chunks.length; i++) await this.t.writeNoResponse(UUID.payload[i], chunks[i]);
    await this.t.writeNoResponse(UUID.ctrl, ctrl);
    return done;
  }

  /**
   * Full handshake. After this, frames are encrypted and the session is authenticated.
   * @param {Buffer|string} password  device password ('' if not paired)
   */
  async handshake(password) {
    // 1. getPeriphPubKey (plaintext) -> [OK, pub(64), seed(4)]
    const r = await this.transceive(cmd.getPeriphPubKey(), { crypted: false });
    if (r[0] !== cmd.RET.OK) throw new Error(`getPeriphPubKey -> ${r[0]}`);
    const periphPub = r.subarray(1, 65);
    const seed = r.subarray(65, 69);
    // 2. derive the secret
    const kp = generateKeyPair();
    const { key, iv } = deriveSecret(kp, Buffer.from(periphPub), Buffer.from(seed));
    // The device sets the secret while processing setCentralPubKey and already encrypts THAT reply,
    // so we get the cipher ready first (the request is plaintext; the reply is
    // decoded according to the `crypted` flag in its CTRL).
    this.cipher = { key, iv };
    // 3. setCentralPubKey (plaintext request) -> [OK]
    const r2 = await this.transceive(cmd.setCentralPubKey(publicKeyXY(kp)), { crypted: false });
    if (r2[0] !== cmd.RET.OK) throw new Error(`setCentralPubKey -> ${r2[0]}`);
    // 4. authenticate (encrypted) -> [OK]
    const r3 = await this.transceive(cmd.authenticate(password), { crypted: true });
    if (r3[0] !== cmd.RET.OK) throw new Error(`authenticate -> ${r3[0]}`);
    return true;
  }
}
