// SmartHalo 2 emulator to validate the recovery flow end to end (no hardware).
// Models: STM32 (SPIFFS + UART console + nRF power control) and nRF (BLE auth).
// The nRF only advertises/is reachable if the STM powers it (StandbyState == Off or missing).
import { MockDevice } from '../../sh2-core/test/mock-device.mjs';
import { UUID } from '../../sh2-core/src/frame.mjs';

export const STANDBY = { Off: 0, Sleep: 1, Armed: 2, Travel: 3 };

function hexdump(buf) {
  let out = '';
  for (let i = 0; i < buf.length; i += 16) {
    const chunk = buf.subarray(i, i + 16);
    const hex = [...chunk].map((b) => b.toString(16).padStart(2, '0')).join(' ');
    const asc = [...chunk].map((b) => (b >= 32 && b < 127 ? String.fromCharCode(b) : '.')).join('');
    out += `${i.toString(16).padStart(8, '0')}: ${hex.padEnd(47)}  ${asc}\n`;
  }
  return out.trimEnd();
}

export class Sh2Device {
  /**
   * @param {{devicePass?:string, salt:Buffer, standby?:number, armedMode?:boolean, tapCode?:number, tapLen?:number}} o
   */
  constructor({ devicePass = '', salt, standby = STANDBY.Armed, armedMode = false, tapCode = 0b01010, tapLen = 5 } = {}) {
    this.salt = salt;
    this._devicePass = devicePass;          // lives on the nRF, survives STM reboots
    this.spiffs = new Map();                // the STM32's "external flash"
    this.spiffs.set('StandbyState', Buffer.from([standby]));
    this.spiffs.set('ArmedMode', Buffer.from([armedMode ? 1 : 0]));
    const ac = Buffer.alloc(9);             // AlarmConfig: u32 seed + {code,length,mode,severity,allowStandby}
    ac.writeUInt32LE(0x11223344, 0); ac[4] = tapCode; ac[5] = tapLen; ac[6] = 1; ac[7] = 1; ac[8] = 0;
    this.spiffs.set('AlarmConfig', ac);
    this.nrf = null; this.blePowered = false;
    this.boot();
  }

  boot() {
    if (this.nrf) this._devicePass = this.nrf.password.toString();   // keep the password before powering off
    const ss = this.spiffs.get('StandbyState');
    const standby = ss && ss.length ? ss[0] : STANDBY.Off;           // missing => Off
    this.blePowered = standby === STANDBY.Off;
    this.nrf = this.blePowered
      ? new MockDevice({ password: this._devicePass, paired: this._devicePass.length > 0, salt: this.salt })
      : null;
  }

  // -------- BLE side (nRF) --------
  scanBLE() { return this.blePowered ? { name: 'smarthalo', service: UUID.service } : null; }
  bleTransport() {
    if (!this.blePowered || !this.nrf) throw new Error('BLE unavailable: the STM keeps the nRF unpowered (standby)');
    return this.nrf;   // MockDevice already implements writeNoResponse/subscribe (Transport interface)
  }
  get devicePass() { return this.nrf ? this.nrf.password.toString() : this._devicePass; }

  // -------- STM32 UART console (USART1) --------
  uart(line) {
    const parts = line.trim().split(/\s+/);
    const cmd = parts[0], arg = parts[1];
    switch (cmd) {
      case 'help': return 'help ls df xxd rm format reboot power version';
      case 'ls': return [...this.spiffs.keys()].join('\n') || '(empty)';
      case 'xxd': { const f = this.spiffs.get(arg); return f ? hexdump(f) : `xxd: ${arg}: No such file`; }
      case 'rm': return this.spiffs.delete(arg) ? `removed '${arg}'` : `rm: ${arg}: No such file`;
      case 'format': this.spiffs.clear(); return 'formatted external FS';
      case 'reboot': this.boot(); return "rebooting...\r\nLet's Ride";
      case 'power': return this.blePowered ? 'nRF: powered (advertising)' : 'nRF: OFF (standby)';
      default: return `unknown command: ${cmd}`;
    }
  }
}
