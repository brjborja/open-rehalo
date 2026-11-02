// Reads the 16-byte salt from the public firmware source (auth.c) instead of hard-coding it in
// this repo. Set SH2_FIRMWARE_SRC to the path of your copy of auth.c.
import { readFileSync } from 'node:fs';

export function readSalt(path = process.env.SH2_FIRMWARE_SRC) {
  if (!path) throw new Error('Set SH2_FIRMWARE_SRC to the path of your copy of the firmware auth.c');
  const src = readFileSync(path, 'utf8');
  const m = src.match(/auth_salt\s*\[\s*\]\s*=\s*\{([^}]*)\}/);
  if (!m) throw new Error('auth_salt not found in ' + path);
  const bytes = m[1].split(',').map((x) => parseInt(x.trim(), 16)).filter((n) => !Number.isNaN(n));
  if (bytes.length !== 16) throw new Error(`salt has ${bytes.length} bytes (expected 16)`);
  return Buffer.from(bytes);
}
