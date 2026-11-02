// Simulated SmartHalo 2 for tests: implements the device side of handshake + auth + recovery.
import { createECDH, randomBytes, createHash } from 'node:crypto';
import { UUID, encodeMessage, decodeReply } from '../src/frame.mjs';
import * as cmd from '../src/commands.mjs';

export class MockDevice {
  constructor({ password = '', paired = false, salt } = {}) {
    this.password = Buffer.from(password);
    this.paired = paired;
    this.salt = salt ?? randomBytes(16);
    this.ecdh = createECDH('prime256v1'); this.ecdh.generateKeys();
    this.seed = randomBytes(4);
    this.cipher = undefined;
    this.authed = false;
    this.subs = new Map();
    this.reqAccum = [];
    this.tapCodeCleared = null; // would be set to true if a clearing ALARM_SETCONFIG arrives
  }
  async subscribe(uuid, cb) { this.subs.set(uuid, cb); }
  async writeNoResponse(uuid, data) {
    if (UUID.payload.indexOf(uuid) !== -1) { this.reqAccum.push(Buffer.from(data)); return; }
    if (uuid === UUID.ctrl) { this._process(Buffer.from(data)); return; }
    throw new Error('unexpected uuid ' + uuid);
  }
  _reply(buf) {
    const { chunks, ctrl } = encodeMessage(buf, this.cipher);
    Promise.resolve().then(() => {
      chunks.forEach((c, i) => this.subs.get(UUID.payload[i])?.(c));
      this.subs.get(UUID.ctrl)?.(ctrl);
    });
  }
  _process(ctrl) {
    const req = decodeReply(ctrl, Buffer.concat(this.reqAccum), this.cipher);
    this.reqAccum = [];
    const [svc, c] = [req[0], req[1]];
    if (svc === 0 && c === 1) {                       // getPeriphPubKey
      return this._reply(Buffer.concat([Buffer.from([cmd.RET.OK]), this.ecdh.getPublicKey().subarray(1), this.seed]));
    }
    if (svc === 0 && c === 2) {                        // setCentralPubKey
      const secret = this.ecdh.computeSecret(Buffer.concat([Buffer.from([0x04]), req.subarray(2, 66)]));
      this.seed.copy(secret, 16, 0, 4);
      this.cipher = { key: secret.subarray(0, 16), iv: secret.subarray(16, 32) };
      return this._reply(Buffer.from([cmd.RET.OK]));
    }
    if (svc === 0 && c === 3) {                        // authenticate
      const pw = req.subarray(2);
      const ok = pw.equals(this.password);
      if (ok) this.authed = true;
      return this._reply(Buffer.from([ok ? cmd.RET.OK : cmd.RET.FAIL]));
    }
    if (svc === 0 && c === 4) {                        // setPassword (needs authed)
      if (!this.authed) return this._reply(Buffer.from([cmd.RET.DENIED]));
      this.password = Buffer.from(req.subarray(2));
      this.paired = this.password.length > 0;
      return this._reply(Buffer.from([cmd.RET.OK]));
    }
    if (svc === 0 && c === 6) {                        // getSeed
      this.seed = randomBytes(4);
      return this._reply(Buffer.concat([Buffer.from([cmd.RET.OK]), this.seed]));
    }
    if (svc === 0 && c === 7) {                        // resetPassword
      const challenge = createHash('sha256').update(this.seed).update(this.salt).digest();
      if (Buffer.from(req.subarray(2)).equals(challenge)) {
        this.password = Buffer.from(''); this.paired = false;
        return this._reply(Buffer.from([cmd.RET.OK]));
      }
      return this._reply(Buffer.from([cmd.RET.FAIL]));
    }
    if (svc === 3 && c === 3) {                        // ALARM_SETCONFIG (tap code clearing)
      this.tapCodeCleared = true;
      return this._reply(Buffer.from([cmd.RET.OK]));
    }
    if (svc >= 1 && svc <= 4) {                        // STM acks commands (light/sound/alarm/device)
      return this._reply(Buffer.from([cmd.RET.OK]));
    }
    return this._reply(Buffer.from([cmd.RET.UNIMPLEMENTED]));
  }
}
