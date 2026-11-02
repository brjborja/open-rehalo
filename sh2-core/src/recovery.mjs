// SmartHalo 2 — recovery of your own device when its pairing/PIN is unknown.
// See docs/protocol/pairing.md. Uses an already opened Session (open()).
import * as cmd from './commands.mjs';
import { resetPasswordChallenge } from './crypto.mjs';
import { randomBytes } from 'node:crypto';

/** Generates a 32-byte ASCII device password (as the official app did). */
export function generateDevicePassword() {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const r = randomBytes(32);
  let s = '';
  for (let i = 0; i < 32; i++) s += alphabet[r[i] % alphabet.length];
  return s;
}

/**
 * Unpairs the device through the reset-challenge path (does NOT need the current password).
 * getSeed (plaintext) -> resetPassword(SHA256(seed||salt)) (plaintext). Erases the BLE password.
 * NOTE: this does NOT erase the tap code (see docs/protocol/pairing.md).
 * @param {import('./session.mjs').Session} session
 * @param {Buffer} salt  16 bytes (from auth.c:auth_salt in the firmware source)
 */
export async function resetPairing(session, salt) {
  const r1 = await session.transceive(cmd.getSeed(), { crypted: false });
  if (r1[0] !== cmd.RET.OK) throw new Error(`getSeed -> ${r1[0]}`);
  const seed = r1.subarray(1, 5);
  const challenge = resetPasswordChallenge(seed, salt);
  const r2 = await session.transceive(cmd.resetPassword(challenge), { crypted: false });
  if (r2[0] !== cmd.RET.OK) throw new Error(`resetPassword rejected (${r2[0]}): your unit's salt/algorithm may differ from the public firmware`);
  return true;
}

/**
 * Re-pairs: handshake with an empty password (freshly unpaired device) and sets the new one.
 * @returns {string} the new password (keep it: this is the only copy).
 */
export async function repair(session, newPassword = generateDevicePassword()) {
  await session.handshake('');                 // device with no password -> empty auth OK
  const r = await session.transceive(cmd.setPassword(newPassword), { crypted: true });
  if (r[0] !== cmd.RET.OK) throw new Error(`setPassword -> ${r[0]}`);
  return newPassword;
}

/**
 * Recovers full access: reset-challenge + re-pair with a new password.
 * After this you control the device over BLE (incl. the alarm), and the old tap code no longer matters.
 * @returns {string} the device's new password.
 */
export async function recoverAccess(session, salt, newPassword) {
  await resetPairing(session, salt);
  return repair(session, newPassword);
}
