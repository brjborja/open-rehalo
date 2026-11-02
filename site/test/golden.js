// The same table as golden.c, on the JavaScript port. Prints the same lines.
const fw = require('../firmware.js');
const leds = new Uint8Array(512);
const lines = [];
const run = (name, n, call) => {
  for (let t = 0; t < n; t++) {
    leds.fill(0);
    const r = call(t);
    lines.push(`${name} ${t} ${r ? 1 : 0} ${Buffer.from(leds.subarray(0, 72)).toString('hex')}`);
  }
};
const c = (h, s, v) => ({ h, s, v });
const green = c(67, 255, 255), orange = c(30, 255, 255), white = c(0, 0, 255);
const call = c(143, 219, 198), rain = c(170, 220, 255), blank = c(0, 0, 0);

run('logo', 340, (t) => fw.logo(leds, t));
run('disconnect', 170, (t) => fw.disconnect(leds, t));
[
  { heading: 90, headingGap: 0, colour: green },
  { heading: 65416, headingGap: 40, colour: orange },
  { heading: 12, headingGap: 200, colour: green },
  { heading: 300, headingGap: -200, colour: green },
  { heading: 0, headingGap: 0, colour: c(17, 255, 255), standby: true },
  { heading: 45, headingGap: 0, colour: orange, off: true },
].forEach((p, i) => run(`pointer${i}`, 200, (t) => fw.pointer(leds, t, p)));
[{ percentage: 62, gap: 20 }, { percentage: 0, gap: 0 }, { percentage: 100, gap: -10 }]
  .forEach((s, i) => run(`speed${i}`, 90, (t) => fw.speedometer(leds, t, s)));
const base = { colour: green, backgroundColour: white, width: 105, gap: 0, repeat: 0 };
[
  { ...base, angle: 90, progress: 0 },
  { ...base, angle: 90, progress: 40, gap: 20, backgroundReady: true },
  { ...base, angle: -90, progress: 70, gap: 5, backgroundReady: true },
  { ...base, angle: 37, progress: 100, gap: 18, backgroundReady: true },
  { ...base, angle: 90, progress: 100, gap: 0, backgroundReady: true },
  { ...base, angle: 0, progress: 100, gap: 100, width: 360, backgroundReady: true },
  { ...base, angle: 0, progress: 0, width: 360 },
].forEach((a, i) => run(`bg${i}`, 170, (t) => fw.angleBackground(leds, t, a)));
[
  { colour: call, backgroundColour: blank, angle: 0, progress: 100, gap: 100, width: 360, repeat: 60, backgroundReady: true },
  { colour: rain, backgroundColour: blank, angle: 0, progress: 100, gap: 100, width: 360, repeat: 10, backgroundReady: true },
].forEach((a, i) => run(`notify${i}`, 700, (t) => fw.angle(leds, t, a)));
run('intro', 120, (t) => fw.angleIntro(leds, t));
run('swipeR', 26, (t) => fw.swipe(leds, t, true, true));
run('swipeL', 26, (t) => fw.swipe(leds, t, false, true));
for (let len = 1; len <= 5; len++) run(`taps${len}`, 1, () => (fw.taps(leds, 0x0a, len, true), 0));
run('armOn', 120, (t) => fw.alarmSettingChange(leds, t, true));
run('armOff', 120, (t) => fw.alarmSettingChange(leds, t, false));
[33, 66, 100, 0].forEach((p) => run(`alarm${p}`, 460, (t) => fw.alarmStateChange(leds, t, p)));
const hours = { hourHsv: c(0, 0, 220), minuteHsv: c(143, 219, 198) };
[
  { ...hours, hour: 10, minute: 10, intro: true },
  { ...hours, hour: 4, minute: 22 },
  { ...hours, hour: 3, minute: 16 },
  { ...hours, hour: 7, minute: 40, intro: true },
].forEach((d, i) => run(`clock${i}`, 420, (t) => fw.clock(leds, t, d)));
[80, 30, 100, 5].forEach((soc) => run(`battery${soc}`, 310, (t) => fw.battery(leds, t, soc)));
console.log(lines.join('\n'));
