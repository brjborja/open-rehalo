// SmartHalo 2 — ECDH P-256 handshake + AES-128-CBC link encryption.
// We act as the "central" (same as the official app). See docs/protocol/ble-link.md §4-5.
//
// On the wire, both periphPubKey and centralPubKey are big-endian X||Y (64 B),
// and the derived shared secret is the big-endian X coordinate (32 B) — the firmware does
// an internal reverse(), but the observable result matches standard ECDH.
import { createECDH, createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

const CURVE = 'prime256v1'; // NIST P-256 / secp256r1

/** The central's ephemeral key pair. */
export function generateKeyPair() {
  const ecdh = createECDH(CURVE);
  ecdh.generateKeys();
  return ecdh;
}

/** Public key in protocol format: big-endian X||Y, 64 bytes (no 0x04 prefix). */
export function publicKeyXY(ecdh) {
  const uncompressed = ecdh.getPublicKey(); // 65 B: 0x04 || X(32) || Y(32)
  if (uncompressed.length !== 65 || uncompressed[0] !== 0x04) {
    throw new Error('unexpected public key');
  }
  return uncompressed.subarray(1); // 64 B
}

/**
 * Derives the link key material.
 * @param {import('node:crypto').ECDH} ecdh  the central's ephemeral pair
 * @param {Buffer} periphPubKeyXY  64 B (big-endian X||Y) returned by getPeriphPubKey
 * @param {Buffer} seed            4 B returned by the device
 * @returns {{key:Buffer, iv:Buffer, secret:Buffer}} key=secret[0:16], iv=secret[16:32]
 */
export function deriveSecret(ecdh, periphPubKeyXY, seed) {
  if (periphPubKeyXY.length !== 64) throw new Error('periphPubKey must be 64 B');
  if (seed.length !== 4) throw new Error('seed must be 4 B');
  const peerUncompressed = Buffer.concat([Buffer.from([0x04]), periphPubKeyXY]);
  const secret = ecdh.computeSecret(peerUncompressed); // 32 B, X coord big-endian
  if (secret.length !== 32) throw new Error('unexpected secret');
  // overwrites [16..19] with the seed (same as the official app and the firmware)
  seed.copy(secret, 16, 0, 4);
  return { key: secret.subarray(0, 16), iv: secret.subarray(16, 32), secret };
}

/** Encrypts an application payload (PKCS#7 to a multiple of 16). Returns the ciphertext. */
export function encrypt(key, iv, plaintext) {
  const c = createCipheriv('aes-128-cbc', key, iv);
  c.setAutoPadding(true); // PKCS#7
  return Buffer.concat([c.update(plaintext), c.final()]);
}

/** Decrypts and removes the PKCS#7 padding. */
export function decrypt(key, iv, ciphertext) {
  const d = createDecipheriv('aes-128-cbc', key, iv);
  d.setAutoPadding(true);
  return Buffer.concat([d.update(ciphertext), d.final()]);
}

/**
 * Password reset challenge = SHA-256( seed(4) || salt(16) ).
 * The `salt` is NOT included here: read it from the firmware source (auth.c, auth_salt).
 */
export function resetPasswordChallenge(seed, salt) {
  if (seed.length !== 4) throw new Error('seed must be 4 B');
  if (salt.length !== 16) throw new Error('salt must be 16 B');
  return createHash('sha256').update(seed).update(salt).digest(); // 32 B
}

export { randomBytes };
