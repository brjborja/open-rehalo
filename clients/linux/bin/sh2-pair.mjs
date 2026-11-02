#!/usr/bin/env node
// Recovers a SmartHalo 2 you own: connect -> reset-challenge -> re-pair with a new password.
// Usage: sh2-pair <MAC> [--password <new>]
import { Session, recovery } from 'sh2-core';
import { DbusTransport } from '../src/dbus-transport.mjs';
import { readSalt } from '../src/find-salt.mjs';

const mac = process.argv[2];
if (!mac) { console.error('usage: sh2-pair <MAC> [--password <new>]'); process.exit(1); }
const pwIdx = process.argv.indexOf('--password');
const newPw = pwIdx !== -1 ? process.argv[pwIdx + 1] : undefined;

const salt = readSalt();
const t = new DbusTransport();
try {
  console.error(`Connecting to ${mac}...`);
  await t.connect(mac);
  const s = new Session(t);
  await s.open();
  console.error('Connected. Resetting the pairing (reset-challenge) and re-pairing...');
  const pw = await recovery.recoverAccess(s, salt, newPw);
  console.error('\n✅ Recovered. NEW device password (save it, this is the only copy):\n');
  console.log(pw);
  console.error('\nThe old tap code no longer blocks your BLE access (arming and disarming are done from the app).');
} catch (e) {
  console.error('\n❌ Error:', e.message);
  process.exitCode = 1;
} finally {
  await t.disconnect();
  process.exit(process.exitCode || 0);
}
