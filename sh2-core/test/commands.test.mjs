import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as cmd from '../src/commands.mjs';

test('frontLight on/off', () => {
  assert.deepEqual([...cmd.frontLight(true)], [1, 4, 1, 0]);
  assert.deepEqual([...cmd.frontLight(false)], [1, 4, 0, 0]);
});
test('frontLightSettings', () => {
  assert.deepEqual([...cmd.frontLightSettings(cmd.LightMode.Blinking, 200)], [1, 16, 1, 200, 0, 0]);
});
test('alarmSetState packs a big-endian i32 + state', () => {
  assert.deepEqual([...cmd.alarmSetState(0x01020304, 1)], [3, 2, 1, 2, 3, 4, 1]);
});
test('auth builders', () => {
  assert.deepEqual([...cmd.getVersions()], [0, 0]);
  assert.deepEqual([...cmd.getPeriphPubKey()], [0, 1]);
  assert.deepEqual([...cmd.getSeed()], [0, 6]);
  assert.equal(cmd.setCentralPubKey(Buffer.alloc(64)).length, 66);
  assert.deepEqual([...cmd.authenticate('AB')], [0, 3, 65, 66]);
});
