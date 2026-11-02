import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { tmpdir } from 'node:os';
import { mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { createApp, UserStore } from '../src/server.mjs';

let server, base;
const secret = 'test-secret';
const CT = 'test-consumer-token';

before(async () => {
  const dir = mkdtempSync(join(tmpdir(), 'sh2srv-'));
  const store = new UserStore(join(dir, 'users.json'));
  server = createApp({ consumerToken: CT, store, secret });
  await new Promise((r) => server.listen(0, r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

// helpers: always send the consumer header (harmless where not required) + optional token
const H = (token) => ({ 'content-type': 'application/json', 'x-consumer-token': CT, ...(token ? { 'x-access-token': token } : {}) });
const req = (method, p, body, token, headers) => fetch(base + p, {
  method, headers: headers ?? H(token), body: body !== undefined ? JSON.stringify(body) : undefined,
});
const post = (p, body, token) => req('POST', p, body, token);
const put = (p, body, token) => req('PUT', p, body, token);
const patch = (p, body, token) => req('PATCH', p, body, token);
const del = (p, body, token) => req('DELETE', p, body, token);
const get = (p, token) => req('GET', p, undefined, token);
const tokenFor = async (email) => (await (await post('/auth/local/signup', { email, password: 'pw' })).json()).access_jwt;

test('health', async () => { assert.equal((await get('/health')).status, 200); });

test('x-consumer-token: login without the header -> 401', async () => {
  const r = await fetch(base + '/auth/local/login', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'x@y.z', password: 'p' }),
  });
  assert.equal(r.status, 401);
});

test('checkEmail returns a raw scalar "false"/"true"', async () => {
  let r = await post('/auth/local/checkEmail', { email: 'a@b.com' });
  assert.equal(r.headers.get('content-type')?.startsWith('text/plain'), true);
  assert.equal((await r.text()).trim(), 'false');
  await post('/auth/local/signup', { email: 'a@b.com', password: 'pw', firstName: 'Ana', lastName: 'B' });
  r = await post('/auth/local/checkEmail', { email: 'a@b.com' });
  assert.equal((await r.text()).trim(), 'true');
});

test('forgot returns the scalar "ok"', async () => {
  const r = await post('/auth/forgot', { email: 'a@b.com', language: 'es' });
  assert.equal((await r.text()).trim(), 'ok');
});

test('signup -> UserResponse (tokens + user without hash)', async () => {
  const r = await post('/auth/local/signup', { email: 'c@b.com', password: 'secret', firstName: 'C', lastName: 'D', language: 'es' });
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.ok(j.access_jwt && j.refresh_jwt);
  assert.equal(j.user.email, 'c@b.com');
  assert.equal(j.user.language, 'es');
  assert.equal(j.user.passwordHash, undefined);
});

test('login ok/wrong + protected whoami', async () => {
  let r = await post('/auth/local/login', { email: 'c@b.com', password: 'wrong' });
  assert.equal(r.status, 401);
  r = await post('/auth/local/login', { email: 'c@b.com', password: 'secret' });
  assert.equal(r.status, 200);
  const { access_jwt } = await r.json();
  assert.equal((await get('/api/v1/users/whoami')).status, 401);           // no token
  r = await get('/api/v1/users/whoami', access_jwt);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).email, 'c@b.com');
});

test('update is PUT, returns "ok"; devicePass shows up in whoami', async () => {
  const { access_jwt } = await (await post('/auth/local/signup', { email: 'd@b.com', password: 'pw' })).json();
  const r = await put('/api/v1/users/update', { user: { devicePass: 'ABC123', firstName: 'Dev' } }, access_jwt);
  assert.equal(r.status, 200);
  assert.equal((await r.text()).trim(), 'ok');
  const u = await (await get('/api/v1/users/whoami', access_jwt)).json();
  assert.equal(u.devicePass, 'ABC123');
  assert.equal(u.firstName, 'Dev');
  // POST to update no longer exists -> 404
  assert.equal((await post('/api/v1/users/update', { user: {} }, access_jwt)).status, 404);
});

test('refresh_tokens uses a {data:{…}} -> {data:[{…}]} envelope', async () => {
  const { refresh_jwt, access_jwt } = await (await post('/auth/local/signup', { email: 'e@b.com', password: 'pw' })).json();
  let r = await post('/auth/local/refresh_tokens', { data: { refresh_jwt } });
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.ok(Array.isArray(j.data) && j.data[0].access_jwt, 'response {data:[{access_jwt,…}]}');
  // an access token is not valid as a refresh token
  r = await post('/auth/local/refresh_tokens', { data: { refresh_jwt: access_jwt } });
  assert.equal(r.status, 401);
});

test('v2 configs: PUT then GET (auth + consumer)', async () => {
  const { access_jwt } = await (await post('/auth/local/signup', { email: 'f@b.com', password: 'pw' })).json();
  const uid = 1;
  let r = await put(`/api/v2/users/${uid}/configs`, { user_id: uid, configs: { units: 'metric' } }, access_jwt);
  assert.equal((await r.json()).success, true);
  r = await get(`/api/v2/users/${uid}/configs`, access_jwt);
  const j = await r.json();
  assert.equal(j.success, true);
  assert.deepEqual(j.configs, { units: 'metric' });
  // no consumer token -> 401
  r = await fetch(base + `/api/v2/users/${uid}/configs`, { headers: { 'x-access-token': access_jwt } });
  assert.equal(r.status, 401);
});

test('v2 favourites + dfu + rides stubs', async () => {
  const { access_jwt } = await (await post('/auth/local/signup', { email: 'g@b.com', password: 'pw' })).json();
  assert.equal((await (await post('/api/v2/users/1/favourites', { label: 'home', lat: 1, lng: 2 }, access_jwt)).json()), true);
  assert.equal((await (await get('/api/v2/users/1/favourites', access_jwt)).json()).length, 1);
  assert.deepEqual(await (await get('/v2/dfu?firmware_version=1.0&device_model=SH2', access_jwt)).json(), { data: [] });
  assert.deepEqual(await (await get('/api/v1/users/rides', access_jwt)).json(), []);
});

// ---- Real rides (persistent) ----
const RIDE = {
  start: '2026-10-27T10:00:00Z', end: '2026-10-27T10:30:00Z',
  distance: 5000, averageSpeed: 18.5, elevation: 42, calories: 300,
  stamp: 1730000000000, duration: 1800, maxSpeed: 30, co2: 1.2,
  markers: [
    { coords: { accuracy: 5, speed: 4.2, latitude: 45.5, longitude: -73.6, heading: 90, altitude: 20 }, timestamp: 1730000000000 },
    { coords: { accuracy: 6, speed: 5.0, latitude: 45.51, longitude: -73.61, heading: 95, altitude: 22 }, timestamp: 1730000010000 },
  ],
};

test('rides/sync -> [[RideMarker]] with ride_id; GET rides -> [SHPastRide] camelCase', async () => {
  const token = await tokenFor('rides1@b.com');
  const uid = (await (await get('/api/v1/users/whoami', token)).json()).id;
  const sync = await (await post('/api/v1/users/rides/sync', [RIDE], token)).json();
  assert.ok(Array.isArray(sync) && Array.isArray(sync[0]), 'shape [[RideMarker]]');
  const rideId = sync[0][0].ride_id;                       // what the official app reads
  assert.equal(typeof rideId, 'number');
  assert.equal(sync[0].length, 2);                         // one RideMarker per uploaded marker
  assert.equal(sync[0][0].latitude, 45.5);

  const list = await (await get('/api/v1/users/rides', token)).json();
  assert.equal(list.length, 1);
  const sp = list[0];
  assert.equal(sp.id, rideId);
  assert.equal(sp.averageSpeed, 18.5);                     // camelCase (SHPastRide, default Gson)
  assert.equal(sp.distance, 5000);
  assert.equal(sp.user_id, uid);
  assert.ok(sp.createdAt && sp.updatedAt && sp.stamp === '1730000000000');
  assert.equal(sp.integration, null);
});

test('v2 rides: GET -> {data:[CloudRide]} snake_case with markers', async () => {
  const token = await tokenFor('rides2@b.com');
  const rideId = (await (await post('/api/v1/users/rides/sync', [RIDE], token)).json())[0][0].ride_id;
  const r = await (await get(`/v2/users/me/rides/${rideId}`, token)).json();
  assert.ok(Array.isArray(r.data) && r.data.length === 1);
  const cr = r.data[0];
  assert.equal(cr.average_speed, 18.5);                    // snake_case (@SerializedName)
  assert.equal(cr.created_at !== undefined, true);
  assert.equal(cr.markers.length, 2);
  assert.equal(cr.markers[0].latitude, 45.5);
  assert.equal(cr.significant_markers.length, 2);
  // unknown id -> {data:[]}
  assert.deepEqual(await (await get('/v2/users/me/rides/999999', token)).json(), { data: [] });
});

test('v2 rides: PATCH {data:PatchRideRequest} -> updated CloudRide; DELETE removes it', async () => {
  const token = await tokenFor('rides3@b.com');
  const rideId = (await (await post('/api/v1/users/rides/sync', [RIDE], token)).json())[0][0].ride_id;
  const patched = await (await patch(`/v2/users/me/rides/${rideId}`, { data: { distance: 9999, average_speed: 20 } }, token)).json();
  assert.equal(patched.data[0].distance, 9999);
  assert.equal(patched.data[0].average_speed, 20);
  assert.equal(patched.data[0].calories, 300);             // untouched fields are kept
  // DELETE -> Boolean true and it disappears from the list
  assert.equal(await (await del(`/api/v2/rides/${rideId}`, undefined, token)).json(), true);
  assert.equal((await (await get('/api/v1/users/rides', token)).json()).length, 0);
});

test('rides/sync: re-uploading the same stamp does not duplicate (dedup by PK stamp)', async () => {
  const token = await tokenFor('rides4@b.com');
  await post('/api/v1/users/rides/sync', [RIDE], token);
  await post('/api/v1/users/rides/sync', [{ ...RIDE, distance: 7777 }], token);
  const list = await (await get('/api/v1/users/rides', token)).json();
  assert.equal(list.length, 1);
  assert.equal(list[0].distance, 7777);                    // updated in place
});

// ---- Real favourites ----
test('favourites: POST (all fields) / GET (id, favourite_type, lat/lng) / DELETE form-urlencoded', async () => {
  const token = await tokenFor('fav1@b.com');
  const uid = (await (await get('/api/v1/users/whoami', token)).json()).id;
  assert.equal(await (await post('/api/v2/users/1/favourites',
    { user_id: uid, favourite_type: 'HOME', address: '1 Main St', label: 'home', lat: 45.5, lng: -73.6 }, token)).json(), true);
  const favs = await (await get('/api/v2/users/1/favourites', token)).json();
  assert.equal(favs.length, 1);
  const f = favs[0];
  assert.equal(typeof f.id, 'number');
  assert.equal(f.favourite_type, 'HOME');
  assert.equal(f.address, '1 Main St');
  assert.equal(f.label, 'home');
  assert.equal(f.lat, 45.5);
  assert.equal(f.lng, -73.6);
  assert.equal(f.user_id, uid);
  // DELETE via form-urlencoded favourite_id (as the app does)
  const dr = await fetch(base + '/api/v2/users/1/favourites', {
    method: 'DELETE',
    headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-consumer-token': CT, 'x-access-token': token },
    body: `favourite_id=${f.id}`,
  });
  assert.equal(await dr.json(), true);
  assert.equal((await (await get('/api/v2/users/1/favourites', token)).json()).length, 0);
});

// ---- Configs: DELETE removes keys ----
test('v2 configs: DELETE removes only the given keys', async () => {
  const token = await tokenFor('cfg1@b.com');
  await put('/api/v2/users/1/configs', { user_id: '1', configs: { units: 'metric', theme: 'dark' } }, token);
  assert.equal(await (await del('/api/v2/users/1/configs', { user_id: '1', configs: { theme: '' } }, token)).json(), true);
  const cfg = await (await get('/api/v2/users/1/configs', token)).json();
  assert.deepEqual(cfg.configs, { units: 'metric' });
});
