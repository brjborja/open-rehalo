// End-to-end verification of the mock path WITHOUT Electron and WITHOUT hardware:
// drives the exact same DeviceManager the GUI uses, over the emulator backend.
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DeviceManager } from '../src/device-manager.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

function makeManager() {
  const events = [];
  const m = new DeviceManager({ srcBase: repoRoot, emit: (name, payload) => events.push({ name, payload }) });
  return { m, events };
}

test('mock: scan -> connect -> recover -> light on/off', async () => {
  const { m } = makeManager();
  await m.setMode('mock');

  const scan = await m.scan(10);
  assert.equal(scan.ok, true);
  assert.ok(scan.devices.length >= 1, 'at least one emulated SmartHalo should advertise');
  const dev = scan.devices[0];
  assert.match(dev.name, /halo/i);

  const conn = await m.connect(dev.id, dev.name);
  assert.equal(conn.ok, true);
  assert.equal(m.authed, false, 'not authenticated yet after connecting');

  const rec = await m.recover();
  assert.equal(rec.ok, true);
  assert.equal(typeof rec.password, 'string');
  assert.equal(rec.password.length, 32, 'the new password is 32 chars');
  assert.equal(m.authed, true, 'recover authenticates the session');

  const on = await m.frontLight(true);
  assert.equal(on.ok, true);
  assert.equal(on.ret, 0, 'the device answers RET.OK');
  assert.equal(m.light.on, true);

  const off = await m.frontLight(false);
  assert.equal(off.ok, true);
  assert.equal(m.light.on, false);

  const br = await m.setBrightness(180);
  assert.equal(br.ok, true);
  assert.equal(m.light.brightness, 180);

  for (const a of ['arm', 'disarm', 'report']) {
    const r = await m.alarm(a);
    assert.equal(r.ok, true, `alarm ${a} -> OK`);
  }

  const info = await m.deviceInfo();
  assert.equal(info.ok, true);
  assert.equal(info.info.password, rec.password);

  await m.disconnect();
  assert.equal(m.session, null);
});

test('mock: re-authenticate with the recovered password on a fresh connection', async () => {
  const { m } = makeManager();
  await m.setMode('mock');
  const scan = await m.scan(10);
  const dev = scan.devices[0];

  await m.connect(dev.id, dev.name);
  const rec = await m.recover();
  assert.equal(rec.ok, true);
  await m.disconnect();

  // reconnect and authenticate with the password we just set
  await m.connect(dev.id, dev.name);
  const auth = await m.authenticate(rec.password);
  assert.equal(auth.ok, true, 'the recovered password authenticates a new session');
  assert.equal(m.authed, true);
  const on = await m.frontLight(true);
  assert.equal(on.ok, true);
  await m.disconnect();
});

test('mock: controls are rejected before authentication', async () => {
  const { m } = makeManager();
  await m.setMode('mock');
  const scan = await m.scan(10);
  await m.connect(scan.devices[0].id, scan.devices[0].name);
  const r = await m.frontLight(true);
  assert.equal(r.ok, false, 'controls are unavailable without authentication');
  await m.disconnect();
});
