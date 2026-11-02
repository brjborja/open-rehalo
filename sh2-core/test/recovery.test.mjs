import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MockDevice } from './mock-device.mjs';
import { Session } from '../src/session.mjs';
import { recoverAccess, resetPairing, repair } from '../src/recovery.mjs';

test('recoverAccess: device paired with an unknown password -> recovers with a new one', async () => {
  const salt = Buffer.alloc(16, 0x5a);
  const dev = new MockDevice({ password: 'OLD-UNKNOWN-PASSWORD', paired: true, salt });
  const s = new Session(dev);
  await s.open();

  // We don't know the password; we recover with the firmware salt.
  const newPassword = await recoverAccess(s, salt);

  assert.equal(newPassword.length, 32, 'new password is 32 bytes');
  assert.ok(dev.paired, 'the device ends up paired');
  assert.ok(Buffer.from(newPassword).equals(dev.password), 'the device accepts the new password');
});

test('resetPairing fails if the salt does not match (different unit)', async () => {
  const dev = new MockDevice({ password: 'X', paired: true, salt: Buffer.alloc(16, 0x11) });
  const s = new Session(dev);
  await s.open();
  await assert.rejects(() => resetPairing(s, Buffer.alloc(16, 0x22)), /resetPassword rejected/);
});

test('after recovery, a new handshake with the new password authenticates', async () => {
  const salt = Buffer.alloc(16, 0x5a);
  const dev = new MockDevice({ password: 'old', paired: true, salt });
  let s = new Session(dev); await s.open();
  const newPassword = await recoverAccess(s, salt);
  // new session (like a reconnection) authenticating with the new password
  dev.cipher = undefined; dev.authed = false;
  s = new Session(dev); await s.open();
  await s.handshake(newPassword); // does not throw => OK
  assert.ok(s.cipher);
});
