// Scenarios and canvas for the ring. The frames come from firmware.js, a verified port of the ring's
// own animations. Each scenario plays what the app sends the ring (SH2Protocol: NavDirector,
// CompassDirector, Commands.notification), with the long stretches of a ride shortened.
// The spark is the rehalo mark and the tally is scroll progress: neither exists on the device.
(() => {
  const FW = window.SHFirmware;
  const { hsv, LED_COUNT, RGB_LED_COUNT } = FW;
  const SPARK = 3;                                // the mark's 45° position
  const LIME = [198, 255, 61];
  const TICK_MS = 10;

  const GREEN = hsv(67, 255, 255);                // NavColour.turn
  const OFF_PATH = hsv(30, 255, 255);             // NavColour.offPath
  const WHITE = hsv(0, 0, 255);
  const BLANK = hsv(0, 0, 0);
  const CALL = hsv(143, 219, 198);                // Commands.incomingCall
  const RAIN = hsv(170, 220, 255);                // Commands.rainAlert
  const compassColour = (p) => hsv(17 + Math.trunc((p / 100) * 50), 255, 255);   // NavColour.progress

  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const scenario = (segments, stillAt = 0) => {
    let start = 0;
    segments.forEach((s) => { s.start = start; start += s.ticks; });
    return { segments, length: start, stillAt };
  };
  const dark = (ticks, label = '') => ({ ticks, label });

  const turn = { colour: GREEN, backgroundColour: WHITE, angle: 90, width: 105, repeat: 0 };
  const turnFixes = [[12, 86], [29, 74], [46, 62], [63, 50], [80, 35]].map(([progress, metres], i, all) => ({
    ticks: 100,
    label: `Right turn in ${metres} m`,
    draw: (leds, t) => FW.angleBackground(leds, t, {
      ...turn, progress, gap: progress - (i ? all[i - 1][0] : 0), backgroundReady: true,
    }),
  }));

  const pointerSteps = (steps) => steps.map(({ heading, gap, colour, ticks, label }) => ({
    ticks,
    label,
    draw: (leds, t) => FW.pointer(leds, t, { heading: heading & 0xffff, headingGap: gap, colour }),
  }));

  const arrival = [
    {
      ticks: 50,
      label: 'Arrived',
      draw: (leds, t) => FW.angleBackground(leds, t, { ...turn, angle: 0, width: 360, progress: 0, gap: 0 }),
    },
    {
      ticks: 290,
      label: 'Arrived',
      draw: (leds, t) => FW.angleBackground(leds, t, {
        ...turn, angle: 0, width: 360, progress: 100, gap: 100, backgroundReady: true,
      }),
    },
  ];

  const notification = (colour, repeat) => (leds, t) => FW.angle(leds, t, {
    colour, backgroundColour: BLANK, angle: 0, width: 360, progress: 100, gap: 100, repeat, backgroundReady: true,
  });

  const CLOCK = { hour: 10, minute: 10, hourHsv: hsv(0, 0, 220), minuteHsv: CALL, intro: true };
  const swipe = () => ({ ticks: 22, label: 'Next card', draw: (leds, t) => FW.swipe(leds, t, true, true) });

  const SCENARIOS = {
    nav: scenario([
      { ticks: 108, label: 'Route starts', draw: (leds, t) => FW.angleIntro(leds, t) },
      {
        ticks: 50,
        label: 'Right turn in 95 m',
        draw: (leds, t) => FW.angleBackground(leds, t, { ...turn, progress: 0, gap: 0 }),
      },
      ...turnFixes,
      {
        ticks: 230,
        label: 'Turn right now',
        draw: (leds, t) => FW.angleBackground(leds, t, { ...turn, progress: 100, gap: 20, backgroundReady: true }),
      },
      dark(40, 'Riding'),
      ...pointerSteps([
        { heading: -120, gap: 0, colour: OFF_PATH, ticks: 130, label: 'Off route: pointing back' },
        { heading: -70, gap: 50, colour: OFF_PATH, ticks: 110, label: 'Off route: pointing back' },
        { heading: -20, gap: 50, colour: OFF_PATH, ticks: 110, label: 'Off route: pointing back' },
      ]),
      dark(40, 'Back on route'),
      ...arrival,
      dark(70),
    ], 420),

    compass: scenario([
      {
        ticks: 170,
        label: 'Ride to calibrate',
        draw: (leds, t) => FW.pointer(leds, t, { heading: 0, headingGap: 0, colour: compassColour(0), standby: true }),
      },
      ...pointerSteps([40, -15, 25, -30, 10, -20, 5].map((heading, i, all) => ({
        heading,
        gap: heading - (i ? all[i - 1] : 0),
        colour: compassColour((i + 1) * 14),
        ticks: 130,
        label: `Destination ${(1.4 - i * 0.2).toFixed(1)} km away`,
      }))),
      dark(60),
    ], 700),

    alarm: scenario([
      { ticks: 101, label: 'Arming', draw: (leds, t) => FW.alarmSettingChange(leds, t, true) },
      dark(90, 'Armed: the ring stays dark'),
      { ticks: 200, label: 'Bike moved: warning', draw: (leds, t) => FW.alarmStateChange(leds, t, 33) },
      { ticks: 200, label: 'Still moving: warning', draw: (leds, t) => FW.alarmStateChange(leds, t, 66) },
      { ticks: 400, label: 'Alarm sounding', draw: (leds, t) => FW.alarmStateChange(leds, t, 100) },
      { ticks: 101, label: 'iPhone is back: disarmed', draw: (leds, t) => FW.alarmSettingChange(leds, t, false) },
      dark(70),
    ], 340),

    cards: scenario([
      swipe(),
      { ticks: 340, label: 'Clock', draw: (leds, t) => FW.clock(leds, t, CLOCK) },
      swipe(),
      { ticks: 300, label: 'Battery 80%', draw: (leds, t) => FW.battery(leds, t, 80) },
      swipe(),
      { ticks: 150, label: 'Speed 25 km/h', draw: (leds, t) => FW.speedometer(leds, t, { percentage: 62, gap: 62 }) },
      { ticks: 150, label: 'Speed 20 km/h', draw: (leds, t) => FW.speedometer(leds, t, { percentage: 50, gap: -12 }) },
      dark(30),
      { ticks: 40, label: 'Tap: short', draw: (leds) => FW.taps(leds, 0b10, 1, true) },
      { ticks: 80, label: 'Tap: short, long', draw: (leds) => FW.taps(leds, 0b10, 2, true) },
      dark(60),
    ], 500),

    call: scenario([
      { ticks: 560, label: 'Incoming call: pulses for about 30 s', draw: notification(CALL, 60) },
      dark(90),
    ], 75),

    rain: scenario([
      { ticks: 625, label: 'Rain in 20 min', draw: notification(RAIN, 10) },
      dark(110),
    ], 75),

    // The closing image: every LED but one.
    almost: scenario([{
      ticks: 1e9,
      label: '',
      draw: (leds, t) => {
        for (let k = 0; k < LED_COUNT; k++) leds.set(LIME, k * 3);
        spark(leds, t, 0.12, 0.5);
      },
    }], 100),
  };

  function spark(leds, t, floor = 0.7, range = 0.3) {
    const a = floor + range * (0.5 - 0.5 * Math.cos((t / 260) * Math.PI * 2));
    leds.set(LIME.map((c) => Math.round(c * a)), SPARK * 3);
  }

  class Ring {
    constructor(canvas, { state, showTally = false, onLabel } = {}) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.leds = new Uint8Array(512);
      this.showTally = showTally;
      this.onLabel = onLabel;
      this.tally = 0;
      this.shown = 0;
      this.visible = false;
      this.play(state);
      this.resize();
      new ResizeObserver(() => this.resize()).observe(canvas);
      new IntersectionObserver(([e]) => {
        this.visible = e.isIntersecting;
        if (reduceMotion) this.still();
      }).observe(canvas);
    }

    play(state) {
      this.scenario = SCENARIOS[state];
      this.startedAt = performance.now();
      this.label = null;
      if (reduceMotion) this.still();
    }

    still() { this.renderTick(this.scenario.stillAt); }

    resize() {
      const ratio = Math.min(devicePixelRatio || 1, 2);
      const box = this.canvas.getBoundingClientRect();
      this.canvas.width = Math.round(box.width * ratio);
      this.canvas.height = Math.round(box.height * ratio);
      if (reduceMotion) this.still();
    }

    tick(now) { this.renderTick(Math.floor((now - this.startedAt) / TICK_MS)); }

    renderTick(tick) {
      const { scenario: sc, leds } = this;
      const t = tick % sc.length;
      const segment = sc.segments.find((s) => t < s.start + s.ticks);
      leds.fill(0);
      if (segment.draw) segment.draw(leds, t - segment.start);
      if (segment.label !== this.label) {
        this.label = segment.label;
        if (this.onLabel) this.onLabel(segment.label);
      }
      this.paint();
    }

    paint() {
      const { ctx, canvas, leds } = this;
      const size = canvas.width;
      if (!size) return;
      const c = size / 2;
      ctx.clearRect(0, 0, size, size);
      const radius = size * (this.showTally ? 0.33 : 0.36);
      const length = size * 0.062;
      const width = size * 0.036;
      ctx.lineCap = 'round';

      for (let k = 0; k < LED_COUNT; k++) {
        const a = (k * 15 - 90) * (Math.PI / 180);
        const x = c + Math.cos(a) * radius;
        const y = c + Math.sin(a) * radius;
        const dx = -Math.sin(a) * length * 0.5;
        const dy = Math.cos(a) * length * 0.5;
        const segment = (colour) => {
          ctx.lineWidth = width;
          ctx.strokeStyle = colour;
          ctx.beginPath();
          ctx.moveTo(x - dx, y - dy);
          ctx.lineTo(x + dx, y + dy);
          ctx.stroke();
        };
        segment('rgba(242,244,247,.07)');
        const [r, g, b] = leds.subarray(k * 3, k * 3 + 3);
        const peak = Math.max(r, g, b);
        if (peak < 3) continue;
        // LED drive values to screen: keep the hue, lift dim levels the way the eye sees an LED.
        const alpha = (peak / 255) ** 0.6;
        const scale = 255 / peak;
        const rgb = `${Math.round(r * scale)},${Math.round(g * scale)},${Math.round(b * scale)}`;
        ctx.shadowColor = `rgba(${rgb},${alpha})`;
        ctx.shadowBlur = size * 0.05 * alpha;
        segment(`rgba(${rgb},${alpha})`);
        ctx.shadowBlur = 0;
      }

      if (this.showTally) {
        this.shown += (this.tally - this.shown) * (reduceMotion ? 1 : 0.08);
        for (let i = 0; i < LED_COUNT; i++) {
          const a = (i * 15 - 90) * (Math.PI / 180);
          ctx.fillStyle = i < this.shown - 0.01 ? 'rgb(198,255,61)' : 'rgba(242,244,247,.14)';
          ctx.beginPath();
          ctx.arc(c + Math.cos(a) * size * 0.47, c + Math.sin(a) * size * 0.47, size * 0.0075, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    }
  }

  const rings = [];
  const add = (id, options) => {
    const canvas = document.getElementById(id);
    if (!canvas) return null;
    const ring = new Ring(canvas, options);
    rings.push(ring);
    return ring;
  };

  // The hero: the brand mark starts dim, then the spark lights it.
  const heroSection = document.querySelector('.hero');
  if (reduceMotion) heroSection.classList.add('lit');
  else setTimeout(() => heroSection.classList.add('lit'), 900);

  add('cta-ring', { state: 'almost' });

  // Chapters: the step at the reading line drives the ring, the tally and the phone. On phones the
  // stage fills the top half, so the line sits below it.
  const caption = document.getElementById('stage-caption');
  const stage = add('stage-ring', {
    state: 'nav',
    showTally: true,
    onLabel: (label) => { if (caption) caption.textContent = label; },
  });
  const steps = [...document.querySelectorAll('.step')];
  const shots = [...document.querySelectorAll('#phone-screen img')];
  const activate = (step) => {
    if (step.classList.contains('active')) return;
    steps.forEach((s) => s.classList.toggle('active', s === step));
    if (stage) {
      stage.play(step.dataset.ring);
      stage.tally = Math.round(((steps.indexOf(step) + 1) / steps.length) * (LED_COUNT - 1));
    }
    shots.forEach((img) => img.classList.toggle('on', img.dataset.shot === step.dataset.shot));
  };
  if (steps.length) {
    activate(steps[0]);
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) activate(e.target); });
    }, { rootMargin: matchMedia('(min-width: 900px)').matches ? '-45% 0px -45% 0px' : '-72% 0px -26% 0px' });
    steps.forEach((s) => observer.observe(s));
  }

  const reveal = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add('in'); reveal.unobserve(e.target); }
    });
  }, { rootMargin: '0px 0px -8% 0px' });
  document.querySelectorAll('.reveal').forEach((el) => reveal.observe(el));

  if (reduceMotion) return;
  const loop = (now) => {
    rings.forEach((r) => { if (r.visible) r.tick(now); });
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
})();
