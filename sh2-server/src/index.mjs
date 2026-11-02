import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { createApp, UserStore } from './server.mjs';

const PORT = Number(process.env.PORT || 8730);
const DATA_DIR = process.env.SH2_DATA_DIR || new URL('../data', import.meta.url).pathname;
mkdirSync(DATA_DIR, { recursive: true });

// persisted JWT secret (or from env)
let secret = process.env.SH2_JWT_SECRET;
if (!secret) {
  const sp = `${DATA_DIR}/jwt.secret`;
  if (existsSync(sp)) secret = readFileSync(sp, 'utf8').trim();
  else { secret = randomBytes(32).toString('hex'); writeFileSync(sp, secret); }
}

const store = new UserStore(`${DATA_DIR}/users.json`);
const app = createApp({
  store, secret,
  consumerToken: process.env.SH2_CONSUMER_TOKEN || undefined, // optional; unset = header not required
});
app.listen(PORT, () => console.log(`sh2-server listening on http://0.0.0.0:${PORT}`));
