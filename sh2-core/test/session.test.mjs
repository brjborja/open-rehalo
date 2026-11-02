import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createECDH, randomBytes } from 'node:crypto';
import { Session } from '../src/session.mjs';
import { UUID, encodeMessage, decodeReply } from '../src/frame.mjs';
import * as cmd from '../src/commands.mjs';

// SmartHalo 2 device simulated in software: implements the device side of the handshake with node:crypto
// and replies through notifications using the same bslink framing.
class MockDevice {
  constructor(password) {
    this.password = Buffer.from(password);
    this.ecdh = createECDH('prime256v1'); this.ecdh.generateKeys();
    this.seed = randomBytes(4);
    this.cipher = undefined;        // set while processing setCentralPubKey
    this.subs = new Map();
    this.reqAccum = [];
  }
  // --- Transport face seen by the Session ---
  async subscribe(uuid, cb) { this.subs.set(uuid, cb); }
  async writeNoResponse(uuid, data) {
    const i = UUID.payload.indexOf(uuid);
    if (i !== -1) { this.reqAccum.push(Buffer.from(data)); return; }
    if (uuid === UUID.ctrl) { this._process(Buffer.from(data)); return; }
    throw new Error('unexpected uuid ' + uuid);
  }
  // --- logic ---
  _process(ctrl) {
    const req = decodeReply(ctrl, Buffer.concat(this.reqAccum), this.cipher);
    this.reqAccum = [];
    let reply;
    if (req[0] === 0 && req[1] === 1) {            // getPeriphPubKey
      reply = Buffer.concat([Buffer.from([cmd.RET.OK]), this.ecdh.getPublicKey().subarray(1), this.seed]);
    } else if (req[0] === 0 && req[1] === 2) {      // setCentralPubKey
      const centralPub = req.subarray(2, 66);
      const secret = this.ecdh.computeSecret(Buffer.concat([Buffer.from([0x04]), centralPub]));
      this.seed.copy(secret, 16, 0, 4);
      this.cipher = { key: secret.subarray(0, 16), iv: secret.subarray(16, 32) };
      reply = Buffer.from([cmd.RET.OK]);            // already encrypted (cipher just set)
    } else if (req[0] === 0 && req[1] === 3) {      // authenticate
      const pw = req.subarray(2);
      reply = Buffer.from([pw.equals(this.password) ? cmd.RET.OK : cmd.RET.FAIL]);
    } else {
      reply = Buffer.from([cmd.RET.UNIMPLEMENTED]);
    }
    // delivers the reply through notifications: PAYLOAD[i], then CTRL
    const { chunks, ctrl: rctrl } = encodeMessage(reply, this.cipher);
    Promise.resolve().then(() => {
      chunks.forEach((c, i) => this.subs.get(UUID.payload[i])?.(c));
      this.subs.get(UUID.ctrl)?.(rctrl);
    });
  }
}

test('end-to-end handshake with the correct password', async () => {
  const dev = new MockDevice('s3cr3t-pass');
  const s = new Session(dev);
  await s.open();
  await s.handshake('s3cr3t-pass');
  assert.ok(s.cipher, 'session encrypted after handshake');
});

test('handshake fails with the wrong password', async () => {
  const dev = new MockDevice('right-password');
  const s = new Session(dev);
  await s.open();
  await assert.rejects(() => s.handshake('wrong-password'), /authenticate -> 1/);
});
