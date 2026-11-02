import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Sh2Device, STANDBY } from '../src/sh2-device.mjs';
import { Session } from '../../sh2-core/src/session.mjs';
import * as recovery from '../../sh2-core/src/recovery.mjs';
import * as commands from '../../sh2-core/src/commands.mjs';

const salt = Buffer.alloc(16, 0x5a);
const OLD = 'OLD-UNKNOWN-PASSWORD-32-chars-xx';   // old password we do NOT know

function freshDevice() {
  return new Sh2Device({ devicePass: OLD, salt, standby: STANDBY.Armed, armedMode: false,
                         tapCode: 0b01010, tapLen: 5 });   // tap demo code
}

test('initial state: BLE off because of standby, cannot connect', () => {
  const dev = freshDevice();
  assert.equal(dev.scanBLE(), null, 'not advertising');
  assert.throws(() => dev.bleTransport(), /unpowered/);
});

test('UART: ls/xxd are read-only and show the state', () => {
  const dev = freshDevice();
  assert.match(dev.uart('ls'), /StandbyState/);
  assert.match(dev.uart('ls'), /AlarmConfig/);
  assert.match(dev.uart('xxd StandbyState'), /00000000:/);
  // AlarmConfig reveals the tap code (byte 4 = 0x0a = demo code, byte 5 = 0x05 = length)
  const dump = dev.uart('xxd AlarmConfig');
  assert.match(dump, /44 33 22 11 0a 05/);
});

test('full RECOVERY: rm StandbyState + reboot -> BLE on -> reset-challenge -> re-pair -> control', async () => {
  const dev = freshDevice();

  // (1) BLE off from the start
  assert.equal(dev.scanBLE(), null);

  // (2) UART console: read, then remove the lock
  dev.uart('xxd StandbyState');          // read-only (backup)
  assert.match(dev.uart('rm StandbyState'), /removed/);
  assert.match(dev.uart('rm ArmedMode'), /removed/);
  dev.uart('reboot');

  // (3) the nRF is now powered and advertising
  assert.ok(dev.scanBLE(), 'after removing standby, BLE advertises');
  assert.equal(dev.devicePass, OLD, 'still paired with the old (unknown) password');

  // (4) recovery over BLE without knowing the old password
  const s = new Session(dev.bleTransport());
  await s.open();
  const newPass = await recovery.recoverAccess(s, salt);   // getSeed+resetPassword -> handshake('') -> setPassword(new)

  // (5) re-paired with a NEW password that we do control
  assert.equal(newPass.length, 32);
  assert.equal(dev.devicePass, newPass, 'the device accepts the new password');

  // (6) clean reconnection with the new password + real control (turn the light on)
  dev.nrf.cipher = undefined; dev.nrf.authed = false;      // simulates a reconnection
  const s2 = new Session(dev.bleTransport());
  await s2.open();
  await s2.handshake(newPass);                              // does not throw => authenticated
  const r = await s2.transceive(commands.frontLight(true));
  assert.equal(r[0], commands.RET.OK, 'the light responds OK');
});

test('safeguard: without removing standby, BLE stays unreachable', () => {
  const dev = freshDevice();
  dev.uart('reboot');                     // reboot without deleting anything
  assert.equal(dev.scanBLE(), null, 'a plain reboot does NOT fix it (confirms the diagnosis)');
});
