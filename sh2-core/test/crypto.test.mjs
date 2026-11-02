import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createECDH, createHash } from 'node:crypto';
import {
  generateKeyPair, publicKeyXY, deriveSecret, encrypt, decrypt, resetPasswordChallenge,
} from '../src/crypto.mjs';

test('publicKeyXY returns 64 B X||Y with no prefix', () => {
  const kp = generateKeyPair();
  const xy = publicKeyXY(kp);
  assert.equal(xy.length, 64);
});

test('ECDH: central and "device" derive the same key material', () => {
  // central = our code
  const central = generateKeyPair();
  // device simulated with standard node:crypto (same ECDH observable from the app/fw)
  const device = createECDH('prime256v1');
  device.generateKeys();
  const periphXY = device.getPublicKey().subarray(1); // 64 B
  const seed = Buffer.from([0xde, 0xad, 0xbe, 0xef]);

  const c = deriveSecret(central, periphXY, Buffer.from(seed));

  // device derives its side
  const devSecret = device.computeSecret(central.getPublicKey());
  Buffer.from(seed).copy(devSecret, 16, 0, 4);
  const devKey = devSecret.subarray(0, 16);
  const devIv = devSecret.subarray(16, 32);

  assert.deepEqual(c.key, devKey, 'AES key matches');
  assert.deepEqual(c.iv, devIv, 'IV matches');
});

test('AES-128-CBC round-trip between central and device', () => {
  const central = generateKeyPair();
  const device = createECDH('prime256v1'); device.generateKeys();
  const seed = Buffer.from([1, 2, 3, 4]);
  const c = deriveSecret(central, device.getPublicKey().subarray(1), Buffer.from(seed));
  const devSecret = device.computeSecret(central.getPublicKey());
  Buffer.from(seed).copy(devSecret, 16, 0, 4);

  const msg = Buffer.from([0, 3, 65, 66, 67]); // authenticate "ABC"
  const ct = encrypt(c.key, c.iv, msg);
  assert.equal(ct.length % 16, 0, 'ciphertext is a multiple of 16');
  const pt = decrypt(devSecret.subarray(0, 16), devSecret.subarray(16, 32), ct);
  assert.deepEqual(pt, msg);
});

test('resetPasswordChallenge = SHA-256(seed||salt)', () => {
  const seed = Buffer.from([0x11, 0x22, 0x33, 0x44]);
  const salt = Buffer.alloc(16, 0xab);
  const got = resetPasswordChallenge(seed, Buffer.from(salt));
  const want = createHash('sha256').update(seed).update(salt).digest();
  assert.deepEqual(got, want);
  assert.equal(got.length, 32);
});

test('deriveSecret rejects invalid sizes', () => {
  const kp = generateKeyPair();
  assert.throws(() => deriveSecret(kp, Buffer.alloc(10), Buffer.alloc(4)));
  assert.throws(() => deriveSecret(kp, Buffer.alloc(64), Buffer.alloc(3)));
});
