import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, deriveSecret } from '../src/crypto.mjs';
import { createECDH } from 'node:crypto';
import { encodeMessage, decodeReply, MAX_MESSAGE, MTU } from '../src/frame.mjs';

function makeCipher() {
  const central = generateKeyPair();
  const device = createECDH('prime256v1'); device.generateKeys();
  const seed = Buffer.from([9, 8, 7, 6]);
  const c = deriveSecret(central, device.getPublicKey().subarray(1), Buffer.from(seed));
  return { key: c.key, iv: c.iv };
}

test('plaintext encode/decode round-trip', () => {
  const data = Buffer.from([0, 0]); // getVersions
  const { chunks, ctrl } = encodeMessage(data);
  assert.equal(ctrl[1], 0, 'not encrypted');
  assert.equal(ctrl[0], 2);
  const accum = Buffer.concat(chunks);
  assert.deepEqual(decodeReply(ctrl, accum), data);
});

test('encode splits into a 20-byte MTU', () => {
  const data = Buffer.concat([Buffer.from([1, 4]), Buffer.alloc(40, 0xaa)]); // 42 B
  const { chunks } = encodeMessage(data);
  assert.equal(chunks.length, 3);
  assert.equal(chunks[0].length, MTU);
  assert.equal(chunks[2].length, 2);
});

test('encrypted encode/decode round-trip', () => {
  const cipher = makeCipher();
  const data = Buffer.from([0, 3, 1, 2, 3, 4, 5]); // authenticate
  const { chunks, ctrl } = encodeMessage(data, cipher);
  assert.equal(ctrl[1], 1, 'encrypted');
  assert.equal(ctrl[0] % 16, 0, 'on-wire length is a multiple of 16');
  const accum = Buffer.concat(chunks);
  assert.deepEqual(decodeReply(ctrl, accum, cipher), data);
});

test('rejects messages exceeding MAX_MESSAGE after encryption', () => {
  const cipher = makeCipher();
  // 80 B plaintext -> 96 B encrypted -> too long
  assert.throws(() => encodeMessage(Buffer.alloc(MAX_MESSAGE, 1), cipher));
});
