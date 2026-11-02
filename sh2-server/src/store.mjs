// User store in a JSON file (no dependencies). Enough for a small self-hosted setup;
// can be migrated to SQLite/Postgres later. Does NOT store the plaintext password (only the scrypt hash).
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';

export class UserStore {
  constructor(path) {
    this.path = path;
    this.data = { users: [], seq: 0 };
    if (existsSync(path)) {
      try { this.data = JSON.parse(readFileSync(path, 'utf8')); } catch {}
    } else {
      mkdirSync(dirname(path), { recursive: true });
      this._save();
    }
  }
  _save() { writeFileSync(this.path, JSON.stringify(this.data, null, 2)); }

  findByEmail(email) {
    const e = String(email).toLowerCase();
    return this.data.users.find((u) => u.email.toLowerCase() === e) || null;
  }
  findById(id) { return this.data.users.find((u) => String(u.id) === String(id)) || null; }

  create(u) {
    const id = ++this.data.seq;
    const user = { id, key: randomUUID(), isConfirmed: false, created_at: new Date().toISOString(), ...u };
    this.data.users.push(user);
    this._save();
    return user;
  }
  update(id, patch) {
    const u = this.findById(id);
    if (!u) return null;
    Object.assign(u, patch);
    this._save();
    return u;
  }

  // ---- Rides (per user; monotonic global id so ids are not reused across PATCH/DELETE) ----
  listRides(userId) {
    const u = this.findById(userId);
    return u && Array.isArray(u.rides) ? u.rides : [];
  }
  getRide(userId, rideId) {
    return this.listRides(userId).find((r) => String(r.id) === String(rideId)) || null;
  }
  createRide(userId, ride) {
    const u = this.findById(userId);
    if (!u) return null;
    if (!Array.isArray(u.rides)) u.rides = [];
    this.data.seq_ride = (this.data.seq_ride || 0) + 1;
    const full = { id: this.data.seq_ride, ...ride };
    u.rides.push(full);
    this._save();
    return full;
  }
  updateRide(userId, rideId, patch) {
    const r = this.getRide(userId, rideId);
    if (!r) return null;
    Object.assign(r, patch);
    this._save();
    return r;
  }
  deleteRide(userId, rideId) {
    const u = this.findById(userId);
    if (!u || !Array.isArray(u.rides)) return false;
    const before = u.rides.length;
    u.rides = u.rides.filter((r) => String(r.id) !== String(rideId));
    this._save();
    return u.rides.length < before;
  }
}

/** Returns the public SHUser (without passwordHash). */
export function publicUser(u) {
  if (!u) return null;
  const { passwordHash, ...rest } = u;
  return rest;
}
