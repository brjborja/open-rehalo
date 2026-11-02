// SmartHalo 2 — command payload builders. See docs/protocol/commands.md.
// Each builder returns the PLAINTEXT payload [service, cmd, ...args]; encryption/framing
// is done by frame.mjs. The ids come from the official app and the firmware's command dispatch.

const b = (...xs) => Buffer.from(xs);

// --- Service 0: AUTH ---
export const getVersions      = () => b(0, 0);
export const getPeriphPubKey  = () => b(0, 1);
export const setCentralPubKey = (pubXY) => Buffer.concat([b(0, 2), pubXY]); // pubXY: 64 B
export const authenticate     = (password) => Buffer.concat([b(0, 3), Buffer.from(password)]);
export const setPassword      = (password) => Buffer.concat([b(0, 4), Buffer.from(password)]);
export const getSerial        = (idx = 0) => b(0, 5, idx);
export const getSeed          = () => b(0, 6);
export const resetPassword    = (challenge32) => Buffer.concat([b(0, 7), challenge32]);

// --- Service 1: UI / display + ring ---
export const LightMode = { Normal: 0, Blinking: 1 };
export const frontLight = (on, external = false) => b(1, 4, on ? 1 : 0, external ? 1 : 0);
export const frontLightSettings = (mode, brightness, blinkingLocked = false, silenceRocker = false) =>
  b(1, 16, mode & 0xff, brightness & 0xff, blinkingLocked ? 1 : 0, silenceRocker ? 1 : 0);
export const animOff = () => b(1, 14);
export const setBrightness = (v) => b(1, 15, v & 0xff);

// --- Service 2: sound ---
export const soundPlay = () => b(2, 0);
export const soundStop = () => b(2, 1);

// --- Service 3: alarm ---
export const alarmReport = () => b(3, 0);
export const alarmGetSeed = () => b(3, 1);
/** set_alarm_state(i32, state8): [3,2, i>>24, i>>16, i>>8, i, state] */
export const alarmSetState = (i32, state8) =>
  b(3, 2, (i32 >>> 24) & 0xff, (i32 >>> 16) & 0xff, (i32 >>> 8) & 0xff, i32 & 0xff, state8 & 0xff);

// --- Service 4: device ---
export const enterBootloader = () => b(4, 0);
export const getState = () => b(4, 1);
export const setName = (name) => Buffer.concat([b(4, 2), Buffer.from(name)]);
export const shutdown = () => b(4, 4);

export const RET = { OK: 0, FAIL: 1, DENIED: 2, UNIMPLEMENTED: 3, UNNECESSARY: 4 };
