// The Halo from above, and what it shows in each chapter. The frames come from clips.js: recorded from
// the firmware itself, sent the bytes the app sends (SH2Protocol: NavDirector, CompassDirector,
// DeviceController), with the long stretches of a ride cut out. Each LED is drawn as the light its
// driver gives off, the display as the OLED's own memory.
// The spark is the rehalo mark and the tally is scroll progress: neither exists on the device.
(() => {
  const CLIPS = window.HALO_CLIPS;
  const LED_COUNT = 24;
  const SPARK = 3;                                // the mark's 45° position
  const LIME = [208, 255, 81];                    // the brand's lime, as the LED driver's input

  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // The LED driver (stm firmware, HaloLedsDriver.c): its gamma table, and the value under which it
  // drops the LED to a quarter of the current and stretches the value over the table.
  const GAMMA = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5,
    5, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12, 13, 13, 13, 14, 14, 15, 15, 16, 16,
    17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 23, 24, 24, 25, 25, 26, 27, 27, 28, 29, 29, 30, 31, 32, 32, 33, 34, 35, 35, 36,
    37, 38, 39, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 50, 51, 52, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 66, 67, 68,
    69, 70, 72, 73, 74, 75, 77, 78, 79, 81, 82, 83, 85, 86, 87, 89, 90, 92, 93, 95, 96, 98, 99, 101, 102, 104, 105, 107, 109, 110, 112, 114,
    115, 117, 119, 120, 122, 124, 126, 127, 129, 131, 133, 135, 137, 138, 140, 142, 144, 146, 148, 150, 152, 154, 156, 158, 160, 162, 164, 167, 169, 171, 173, 175,
    177, 180, 182, 184, 186, 189, 191, 193, 196, 198, 200, 203, 205, 208, 210, 213, 215, 218, 220, 223, 225, 228, 231, 233, 236, 239, 241, 244, 247, 249, 252, 255];
  const THRESHOLD = 149;
  // Light out of a channel, 0…1. Under the threshold green and blue use a lower table at that current to
  // match red: the light they give is red's, which is what this follows.
  const LIGHT = GAMMA.map((_, v) => (v >= THRESHOLD ? GAMMA[v] / 255 : GAMMA[Math.floor((v * 255) / THRESHOLD)] / 1020));
  const encode = (x) => (x <= 0.0031308 ? 12.92 * x : 1.055 * x ** (1 / 2.4) - 0.055);
  const EXPOSURE = 1.35;

  const bytes = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const varint = (b, p) => {
    let v = 0;
    for (let shift = 0; ; shift += 7) {
      const x = b[p.i++];
      v += (x & 0x7f) * 2 ** shift;
      if (x < 0x80) return v;
    }
  };

  // LED frames: per frame, the 10 ms ticks since the last one, a 24-bit mask of the LEDs that changed
  // and their RGB. Returns [ms, 72 bytes] with each frame whole.
  function unpackLed(b64) {
    const b = bytes(b64), p = { i: 0 }, frames = [];
    let leds = new Uint8Array(LED_COUNT * 3), t = 0;
    while (p.i < b.length) {
      t += varint(b, p) * 10;
      const mask = b[p.i] | (b[p.i + 1] << 8) | (b[p.i + 2] << 16);
      p.i += 3;
      leds = leds.slice();
      for (let k = 0; k < LED_COUNT; k++) {
        if (mask & (1 << k)) { leds.set(b.subarray(p.i, p.i + 3), k * 3); p.i += 3; }
      }
      frames.push([t, leds]);
    }
    return frames;
  }

  // OLED frames (the SSD1305's memory: 8 pages of 128 columns, bit 0 at the top): per frame, the ticks
  // since the last one, then the runs that changed, each as the bytes skipped, its length and its bytes.
  function unpackOled(b64) {
    const b = bytes(b64), p = { i: 0 }, frames = [];
    let ram = new Uint8Array(1024), t = 0;
    while (p.i < b.length) {
      t += varint(b, p) * 10;
      ram = ram.slice();
      let at = 0;
      for (let runs = varint(b, p); runs > 0; runs--) {
        at += varint(b, p);
        const n = varint(b, p);
        ram.set(b.subarray(p.i, p.i + n), at);
        p.i += n;
        at += n;
      }
      frames.push([t, ram]);
    }
    return frames;
  }

  // The frame showing at `t`: the last one at or before it.
  function frameAt(frames, t) {
    let lo = 0, hi = frames.length - 1;
    if (hi < 0 || frames[0][0] > t) return null;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (frames[mid][0] <= t) lo = mid;
      else hi = mid - 1;
    }
    return frames[lo][1];
  }

  const decoded = {};
  function clip(id) {
    if (!decoded[id]) {
      const c = CLIPS[id];
      decoded[id] = { ...c, led: unpackLed(c.led), oled: unpackOled(c.oled), front: c.front ?? [] };
    }
    return decoded[id];
  }

  // The closing image: every LED but one, lit by the page rather than the firmware.
  const almost = (t) => {
    const leds = new Uint8Array(LED_COUNT * 3);
    for (let k = 0; k < LED_COUNT; k++) leds.set(LIME, k * 3);
    const a = 0.12 + 0.5 * (0.5 - 0.5 * Math.cos((t / 2600) * Math.PI * 2));
    leds.set(LIME.map((c) => Math.round(c * a)), SPARK * 3);
    return leds;
  };

  class Ring {
    constructor(canvas, { state, showTally = false, onLabel } = {}) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.oled = document.createElement('canvas');
      this.oled.width = 512;
      this.oled.height = 256;
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
      this.state = state;
      this.clip = state === 'almost' ? null : clip(state);
      this.startedAt = performance.now();
      this.label = null;
      if (reduceMotion) this.still();
    }

    still() { this.render(this.clip ? this.clip.still : 650); }

    resize() {
      const ratio = Math.min(devicePixelRatio || 1, 2);
      const box = this.canvas.getBoundingClientRect();
      this.canvas.width = Math.round(box.width * ratio);
      this.canvas.height = Math.round(box.height * ratio);
      this.body = null;
      if (reduceMotion) this.still();
    }

    tick(now) { this.render(now - this.startedAt); }

    render(ms) {
      const c = this.clip;
      if (!c) {
        this.paint(almost(ms), null, 0);
        return;
      }
      const t = ms % c.length;
      const segment = c.segments.find(([, at, length]) => t < at + length);
      if (segment[0] !== this.label) {
        this.label = segment[0];
        if (this.onLabel) this.onLabel(this.label);
      }
      this.paint(frameAt(c.led, t), frameAt(c.oled, t), frameAt(c.front, t) || 0);
    }

    // The device's radius: smaller when the tally runs round it.
    get radius() { return this.canvas.width * (this.showTally ? 0.355 : 0.4); }

    // One LED's square, rotated with the ring.
    square(g, k, fill) {
      const { width: size } = this.canvas, c = size / 2, R = this.radius;
      const a = (k * 15 - 90) * (Math.PI / 180), side = R * 0.11;
      g.save();
      g.translate(c + Math.cos(a) * R * 0.83, c + Math.sin(a) * R * 0.83);
      g.rotate(a + Math.PI / 2);
      g.fillStyle = fill;
      g.beginPath();
      g.roundRect(-side / 2, -side / 2, side, side, side * 0.24);
      g.fill();
      g.restore();
    }

    // The shell, the glass and the LEDs behind it, off: drawn once per size.
    paintBody() {
      const size = this.canvas.width, c = size / 2, R = this.radius;
      const body = document.createElement('canvas');
      body.width = body.height = size;
      const g = body.getContext('2d');
      let grad = g.createRadialGradient(c, c - R * 0.2, R * 0.6, c, c, R * 1.09);
      grad.addColorStop(0, '#24272c');
      grad.addColorStop(1, '#101215');
      g.fillStyle = grad;
      g.beginPath();
      g.arc(c, c, R * 1.08, 0, Math.PI * 2);
      g.fill();
      grad = g.createRadialGradient(c - R * 0.3, c - R * 0.35, R * 0.05, c, c, R);
      grad.addColorStop(0, '#16181c');
      grad.addColorStop(0.7, '#08090b');
      grad.addColorStop(1, '#040506');
      g.fillStyle = grad;
      g.beginPath();
      g.arc(c, c, R, 0, Math.PI * 2);
      g.fill();
      g.strokeStyle = 'rgba(255,255,255,0.06)';
      g.lineWidth = R * 0.012;
      g.stroke();
      for (let k = 0; k < LED_COUNT; k++) this.square(g, k, 'rgba(255,255,255,0.03)');
      grad = g.createLinearGradient(c - R, c - R, c + R * 0.2, c + R * 0.4);
      grad.addColorStop(0, 'rgba(255,255,255,0.07)');
      grad.addColorStop(0.45, 'rgba(255,255,255,0)');
      g.fillStyle = grad;
      g.beginPath();
      g.ellipse(c - R * 0.22, c - R * 0.3, R * 0.62, R * 0.38, -0.65, 0, Math.PI * 2);
      g.fill();
      this.body = body;
    }

    setOled(ram) {
      if (ram === this.ram) return;
      this.ram = ram;
      const g = this.oled.getContext('2d');
      g.clearRect(0, 0, 512, 256);
      if (!ram) return;
      g.fillStyle = '#eef2f6';
      for (let i = 0; i < 1024; i++) {
        const byte = ram[i];
        if (!byte) continue;
        const x = (i % 128) * 4, page = i >> 7;
        for (let bit = 0; bit < 8; bit++) if (byte & (1 << bit)) g.fillRect(x, (page * 8 + bit) * 4, 4, 4);
      }
    }

    paint(leds, ram, front) {
      const { ctx: g, canvas } = this;
      const size = canvas.width, c = size / 2, R = this.radius;
      if (!size) return;
      if (!this.body) this.paintBody();
      g.globalCompositeOperation = 'source-over';
      g.clearRect(0, 0, size, size);

      // The front light, ahead of the device.
      const beam = Math.min(1, front / 100);
      if (beam) {
        const grad = g.createRadialGradient(c, c - R * 1.08, 0, c, c - R * 1.08, R * 0.9);
        grad.addColorStop(0, `rgba(255,252,240,${0.85 * beam})`);
        grad.addColorStop(1, 'rgba(255,252,240,0)');
        g.fillStyle = grad;
        g.fillRect(0, 0, size, c);
      }
      g.drawImage(this.body, 0, 0);
      if (beam) {
        g.fillStyle = `rgba(255,252,240,${beam})`;
        g.beginPath();
        g.roundRect(c - R * 0.22, c - R * 1.1, R * 0.44, R * 0.05, R * 0.025);
        g.fill();
      }

      // The display: 128 × 64 across 0.95 of the radius, from a photo of the device.
      this.setOled(ram);
      if (ram) {
        const w = R * 0.95, h = w / 2;
        g.save();
        g.shadowColor = 'rgba(235,242,250,0.3)';
        g.shadowBlur = R * 0.015;
        g.imageSmoothingEnabled = w / 128 < 2.5;
        g.drawImage(this.oled, c - w / 2, c - h / 2, w, h);
        g.restore();
      }

      if (leds) {
        g.globalCompositeOperation = 'lighter';
        for (let k = 0; k < LED_COUNT; k++) {
          const light = [LIGHT[leds[k * 3]], LIGHT[leds[k * 3 + 1]], LIGHT[leds[k * 3 + 2]]];
          const peak = Math.max(...light);
          if (peak < 0.0015) continue;
          const a = (k * 15 - 90) * (Math.PI / 180);
          const x = c + Math.cos(a) * R * 0.83, y = c + Math.sin(a) * R * 0.83;
          const hue = light.map((l) => Math.round(255 * encode(l / peak)));
          const level = Math.min(1, encode(Math.min(1, peak * EXPOSURE)));
          // the bloom on the glass, the diffuser, and the die, which reads as white past what a screen shows
          const bloom = R * (0.1 + 0.1 * level);
          let grad = g.createRadialGradient(x, y, 0, x, y, bloom);
          grad.addColorStop(0, `rgba(${hue},${0.5 * level})`);
          grad.addColorStop(1, `rgba(${hue},0)`);
          g.fillStyle = grad;
          g.fillRect(x - bloom, y - bloom, bloom * 2, bloom * 2);
          this.square(g, k, `rgb(${light.map((l) => Math.round(255 * encode(Math.min(1, l * EXPOSURE))))})`);
          const hot = Math.min(0.75, Math.max(0, peak * EXPOSURE - 0.45) * 0.9);
          if (hot > 0) {
            const r = R * 0.05;
            grad = g.createRadialGradient(x, y, 0, x, y, r);
            grad.addColorStop(0, `rgba(255,255,255,${hot})`);
            grad.addColorStop(1, 'rgba(255,255,255,0)');
            g.fillStyle = grad;
            g.fillRect(x - r, y - r, r * 2, r * 2);
          }
        }
        g.globalCompositeOperation = 'source-over';
      }

      if (this.showTally) {
        this.shown += (this.tally - this.shown) * (reduceMotion ? 1 : 0.08);
        for (let i = 0; i < LED_COUNT; i++) {
          const a = (i * 15 - 90) * (Math.PI / 180);
          g.fillStyle = i < this.shown - 0.01 ? 'rgb(198,255,61)' : 'rgba(242,244,247,.14)';
          g.beginPath();
          g.arc(c + Math.cos(a) * size * 0.47, c + Math.sin(a) * size * 0.47, size * 0.0075, 0, Math.PI * 2);
          g.fill();
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

  // Chapters: the step at the reading line drives the ring, the tally and the phone. On phones in
  // portrait the stage fills the top half, so the line sits below it.
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
    // The side-by-side query from style.css; turning the phone switches layouts, so the line moves too.
    const sideBySide = matchMedia('(min-width: 900px), (orientation: landscape) and (min-width: 600px)');
    let observer;
    const watch = () => {
      observer?.disconnect();
      observer = new IntersectionObserver((entries) => {
        entries.forEach((e) => { if (e.isIntersecting) activate(e.target); });
      }, { rootMargin: sideBySide.matches ? '-45% 0px -45% 0px' : '-72% 0px -26% 0px' });
      steps.forEach((s) => observer.observe(s));
    };
    watch();
    sideBySide.addEventListener('change', watch);
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
