// Demo: runs the recovery against the emulator and prints the session as if it were real.
import { Sh2Device, STANDBY } from './src/sh2-device.mjs';
import { Session } from '../sh2-core/src/session.mjs';
import * as recovery from '../sh2-core/src/recovery.mjs';
import * as commands from '../sh2-core/src/commands.mjs';

const salt = Buffer.alloc(16, 0x5a);
const dev = new Sh2Device({ devicePass: 'OLD-UNKNOWN-PASSWORD-32-chars-xx', salt, standby: STANDBY.Armed });
const P = (s) => console.log(s);
const uart = (c) => { P(`\x1b[36msh2>\x1b[0m ${c}`); const o = dev.uart(c); if (o) P(o); };

P('\n=== SmartHalo 2 — recovery (emulated) ===\n');
P(`[BLE scan] ${dev.scanBLE() ? 'found' : 'NOTHING (nRF powered off by the STM in standby)'}`);
P('\n--- STM32 UART console (115200 8N1) ---');
uart('power');
uart('ls');
uart('xxd StandbyState');
uart('xxd AlarmConfig');        // reveals the tap code (byte 4=0a=demo code, byte 5=05)
uart('rm StandbyState');
uart('rm ArmedMode');
uart('reboot');
uart('power');

P('\n--- BLE (nRF now powered) ---');
const found = dev.scanBLE();
P(`[BLE scan] ${found ? `found: ${found.name} (${found.service})` : 'nothing'}`);
P(`[state] paired with an unknown old password: "${dev.devicePass.slice(0,6)}…"`);

const s = new Session(dev.bleTransport()); await s.open();
P('[sh2-pair] getSeed -> resetPassword(SHA256(seed‖salt)) -> handshake("") -> setPassword(new)…');
const newPass = await recovery.recoverAccess(s, salt);
P(`[sh2-pair] ✅ re-paired. NEW password (keep it): ${newPass}`);

dev.nrf.cipher = undefined; dev.nrf.authed = false;
const s2 = new Session(dev.bleTransport()); await s2.open();
await s2.handshake(newPass);
const r = await s2.transceive(commands.frontLight(true));
P(`[control] light on -> ${r[0] === commands.RET.OK ? 'OK ✅' : 'FAIL'}`);
P('\n=== Recovery validated end to end ===\n');
