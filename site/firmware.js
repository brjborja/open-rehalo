// Port of the SmartHalo 2 ring animations (stm firmware, Src/SmartHaloOS/AnimationsLibrary.c), kept
// close to the C so it can be compared with it: integer widths, float32 maths and truncation matter
// here. site/test/golden.sh runs the original C next to this file and diffs every LED of every frame.
// A clock tick is 10 ms. `leds` is RGB bytes, 3 per LED; the ring has 24, LED k sits at 15k° clockwise.
(function (root) {
  const LED_COUNT = 24;
  const RGB_LED_COUNT = LED_COUNT * 3;
  const f = Math.fround;
  const u8 = (x) => Math.trunc(x) & 0xff;
  const i8 = (x) => (Math.trunc(x) << 24) >> 24;
  const u16 = (x) => Math.trunc(x) & 0xffff;
  const i16 = (x) => (Math.trunc(x) << 16) >> 16;
  const cdiv = (a, b) => Math.trunc(a / b);
  const cmod = (a, b) => a % b;
  const cround = (x) => (x < 0 ? -Math.floor(-x + 0.5) : Math.floor(x + 0.5));
  const hsv = (h, s, v) => ({ h: u8(h), s: u8(s), v: u8(v) });

  const LOGO_COLOURS = [[167, 125], [151, 187], [144, 237], [139, 225], [131, 210], [121, 196],
    [111, 188], [101, 181], [91, 175], [77, 167], [65, 182], [56, 195], [49, 208], [43, 220],
    [38, 233], [32, 219], [24, 203], [14, 187], [2, 171], [245, 200], [237, 237], [232, 209],
    [221, 168], [196, 133]];

  function hsvToRgb(c) {
    if (c.s === 0) return [c.v, c.v, c.v];
    const region = cdiv(c.h, 43);
    const remainder = u8((c.h - region * 43) * 6);
    const p = (c.v * (255 - c.s)) >> 8;
    const q = (c.v * (255 - ((c.s * remainder) >> 8))) >> 8;
    const t = (c.v * (255 - ((c.s * (255 - remainder)) >> 8))) >> 8;
    switch (region) {
      case 0: return [c.v, t, p];
      case 1: return [q, c.v, p];
      case 2: return [p, c.v, t];
      case 3: return [p, q, c.v];
      case 4: return [t, p, c.v];
      default: return [c.v, p, q];
    }
  }

  const ledFromAngle = (angle) => f(f(f(angle) * LED_COUNT) / 360);

  function animationData(startAngle, endAngle, start, end) {
    const startFloat = ledFromAngle(startAngle);
    const endFloat = ledFromAngle(endAngle);
    const startLED = u8(Math.ceil(startFloat));
    const endLED = u8(Math.floor(endFloat));
    const startFraction = f(-1 * f(startFloat - startLED));
    const endFraction = f(endFloat - endLED);
    return {
      startLED,
      endLED,
      startFraction,
      endFraction,
      ledGap: u8(Math.abs(Math.trunc(endLED - startLED + cround(f(endFraction + startFraction))))),
      hueSweep: i16(end.h - start.h),
      direction: endLED > startLED ? 1 : -1,
    };
  }

  function put(leds, idx, rgb) {
    leds[idx] = rgb[0];
    leds[idx + 1] = rgb[1];
    leds[idx + 2] = rgb[2];
  }

  function showArc(leds, startAngle, endAngle, start, end) {
    const d = animationData(startAngle, endAngle, start, end);
    for (let i = 0; i < d.ledGap; i++) {
      const rgb = hsvToRgb({ h: u8(start.h + cdiv(i * d.hueSweep, d.ledGap)), s: start.s, v: start.v });
      put(leds, u8(cmod((d.startLED + i * d.direction) * 3, RGB_LED_COUNT)), rgb);
    }
  }

  function growArc(leds, clock, divisor, startAngle, endAngle, start, end) {
    const d = animationData(startAngle, endAngle, start, end);
    const progress = u8(f(clock / f(divisor)));
    let position = i8(d.startLED * 3 + 3 * progress * d.direction);
    position = i8(position - position % 3);
    for (let i = d.startLED * 3; i <= position; i += 3) {
      const step = cdiv(cmod(i - d.startLED * 3, RGB_LED_COUNT), 3);
      const rgb = hsvToRgb({ h: u8(start.h + cdiv(step * d.hueSweep, d.ledGap)), s: start.s, v: start.v });
      leds[u8(cmod(i, RGB_LED_COUNT))] = rgb[0];
      leds[u8(cmod(i + 1, RGB_LED_COUNT))] = rgb[1];
      leds[u8(cmod(i + 2, RGB_LED_COUNT))] = rgb[2];
    }
  }

  function showLEDsSpin(leds, clock, divisor, startAngle, endAngle, tailAngle, start, end, isFresh) {
    const d = animationData(startAngle, endAngle, start, end);
    const progress = u8(f(clock / f(divisor)));
    const tailCount = u8(ledFromAngle(u16(tailAngle)));
    if (isFresh) leds.fill(0, 0, RGB_LED_COUNT);
    let position = u8(d.startLED * 3 + 3 * progress * d.direction);
    position = u8(position - position % 3);
    const write = (rgb) => {
      for (let k = 0; k < 3; k++) {
        leds[position % RGB_LED_COUNT] = rgb[k];
        position = u8(position + 1);
      }
    };
    write(hsvToRgb({ h: u8(start.h + cdiv(progress * d.hueSweep, d.ledGap)), s: start.s, v: start.v }));
    if (tailCount) {
      position = u8(position - (tailCount + d.direction) * 3 * d.direction);
      for (let i = 0; i < tailCount; i++) {
        const step = cdiv(position % RGB_LED_COUNT, 3);
        write(hsvToRgb({
          h: u8(start.h + cdiv(step * d.hueSweep, d.ledGap)),
          s: start.s,
          v: start.v >> (tailCount - i),
        }));
        if (d.direction === -1) position = u8(position - 6);
      }
    }
  }

  function rainbow(leds, fade) {
    LOGO_COLOURS.forEach(([h, s], i) => {
      const c = hsv(h, s, fade);
      showArc(leds, 270 + 15 * i, 285 + 15 * i, c, c);
    });
  }

  function logo(leds, clockCount) {
    const spinTicks = 33;
    const growTicks = 40;
    const whiteFadeTicks = 50;
    const logoFadeTicks = 100;
    const white = (v) => hsv(14, 0, v);
    let done = 0;
    if (clockCount <= spinTicks) {
      showLEDsSpin(leds, clockCount, f(spinTicks / 19), 60, 360, 60, white(255), white(255), true);
    } else if (clockCount <= spinTicks + growTicks) {
      growArc(leds, clockCount - spinTicks, f(growTicks / 24), 0, 360, white(255), white(255));
    } else if (clockCount <= spinTicks + growTicks + whiteFadeTicks) {
      const clock = clockCount - (spinTicks + growTicks);
      const fade = Math.max(255 - cdiv(clock * 255, whiteFadeTicks), 0);
      showArc(leds, 90, 450, white(fade), white(fade));
    } else {
      const clock = clockCount - (spinTicks + growTicks + whiteFadeTicks);
      let fade = Math.trunc(f((clock * 255) / logoFadeTicks));
      if (fade > 255) {
        fade = Math.trunc(f(255 - f(f(f(clock - logoFadeTicks) * 255) / logoFadeTicks)));
        if (fade < 0) {
          fade = 0;
          done = 1;
        }
      }
      rainbow(leds, fade);
    }
    return done;
  }

  function disconnect(leds, clock) {
    let done = 0;
    let fade = Math.trunc(f((clock * 255) / 50));
    if (fade > 255) {
      fade = Math.trunc(f(255 - f(((clock - 50) * 255) / 100)));
      if (fade < 0) {
        fade = 0;
        done = 1;
      }
    }
    rainbow(leds, fade);
    return done;
  }

  function pointer(leds, clockCount, data) {
    const shiftTicks = 83;
    const fadeTicks = 16;
    leds.fill(0, 0, RGB_LED_COUNT);
    let heading = u16(data.heading + 360 + 7);
    let currentValue = data.colour.v;
    const colour = { ...data.colour };
    if (data.off) {
      if (clockCount < fadeTicks) {
        currentValue = Math.trunc(f(f(1 - f(clockCount / fadeTicks)) * currentValue));
        colour.v = u8(currentValue);
      } else {
        return true;
      }
    }
    const rest = f(1 - f(clockCount / shiftTicks));
    if (data.standby) {
      const clock = clockCount % shiftTicks;
      heading = u16(f(f(f(clock / shiftTicks) * 360) + data.heading));
    } else if (clockCount < shiftTicks) {
      if (data.headingGap > 180) {
        heading = u16(f(heading + f(rest * (360 - data.headingGap))));
      } else if (data.headingGap < -180) {
        heading = u16(f(heading - f(rest * (360 + data.headingGap))));
      } else {
        heading = u16(f(heading - f(rest * data.headingGap)));
      }
    }
    const startAngle = heading - 22;
    const endAngle = heading + 22;
    const d = animationData(startAngle, endAngle, colour, colour);
    showArc(leds, startAngle, endAngle, colour, colour);
    colour.v = u8(f(currentValue * d.startFraction));
    showArc(leds, d.startLED * 15 - 15, d.startLED * 15, colour, colour);
    colour.v = u8(f(currentValue * d.endFraction));
    showArc(leds, d.endLED * 15, d.endLED * 15 + 15, colour, colour);
    return false;
  }

  function speedometer(leds, clockCount, data) {
    const fadeTicks = 50;
    const moveTicks = 50;
    const hueRange = 90;
    leds.fill(0, 0, RGB_LED_COUNT);
    if (data.off && clockCount > fadeTicks) return 1;
    const fade = data.off ? f(1 - f(clockCount / fadeTicks)) : 1;
    const position = !data.off && clockCount < moveTicks && data.gap !== 0
      ? f(f(data.percentage - f(data.gap * f(1 - f(clockCount / moveTicks)))) / 100)
      : f(data.percentage / 100);
    const start = hsv(hueRange, 255, f(255 * fade));
    const end = hsv(f(hueRange * f(1 - position)), 255, 255);
    const startAngle = 240;
    const endAngle = u16(f(startAngle + f(f(17 * position) * 15)));
    const d = animationData(startAngle, endAngle, start, end);
    const fractionalStart = { h: start.h, s: start.s, v: u8(f(start.v * d.endFraction)) };
    const fractionalEnd = { h: end.h, s: end.s, v: u8(f(end.v * d.endFraction)) };
    showArc(leds, startAngle, d.endLED * 15 + 15, fractionalStart, fractionalEnd);
    showArc(leds, startAngle, d.endLED * 15, start, end);
    return 0;
  }

  function angleShow(leds, angle, width, colour, background) {
    const modifier = 15;
    const center = i16(i8(cround(f(angle / modifier))) * modifier);
    const half = f(width / 2);
    const start = f(width >= 15 ? 360 + center - (half - 7.5) : 360 + center - half);
    const end = f(width >= 15 ? 360 + center + (half - 7.5) : 360 + center + half);
    const d = animationData(start, f(end + 15), colour, colour);
    const mix = (key, share) => f(f(colour[key] * share) + f(background[key] * f(1 - share)));
    if (width >= 15) {
      showArc(leds, d.startLED * modifier, d.endLED * modifier, colour, colour);
      if (d.startFraction !== 0) {
        const s = d.startFraction;
        const shown = hsv(cround(mix('h', s)), cround(mix('s', s)), cround(mix('v', s)));
        showArc(leds, d.startLED * 15 - 15, d.startLED * 15, shown, shown);
      }
      if (d.endFraction !== 0) {
        const e = d.endFraction;
        const shown = hsv(cround(mix('h', e)), cround(mix('s', e)), cround(mix('v', e)));
        showArc(leds, d.endLED * 15, d.endLED * 15 + 15, shown, shown);
      }
    } else {
      const progress = f(width / 15);
      const shown = hsv(mix('h', progress), mix('s', progress), mix('v', progress));
      showArc(leds, d.startLED * modifier, d.endLED * modifier, shown, shown);
    }
  }

  function angleBackground(leds, clockCount, data) {
    const fillTicks = 50;
    const fadeTicks = 25;
    if (!data.backgroundReady) {
      if (clockCount < fillTicks) {
        const currentWidth = f((data.width * clockCount) / fillTicks);
        angleShow(leds, data.angle, u16(cround(currentWidth)), data.backgroundColour, data.backgroundColour);
        return 0;
      }
      return 1;
    }
    if ((data.progress >= 100 && clockCount >= fillTicks) || (data.progress >= 100 && data.gap === 0)) {
      let clock = data.gap !== 0 ? clockCount - fillTicks : clockCount;
      clock %= fadeTicks * 2;
      const fade = clock < fadeTicks ? f(1 - f(clock / fadeTicks)) : f(f(clock - fadeTicks) / fadeTicks);
      const fading = { h: data.colour.h, s: data.colour.s, v: u8(f(data.colour.v * fade)) };
      angleShow(leds, data.angle, data.width, fading, fading);
    } else if (clockCount < fillTicks) {
      angleShow(leds, data.angle, data.width, data.backgroundColour, data.backgroundColour);
      const share = f(f(data.progress / 100) - f(f(data.gap / 100) * f(1 - f(clockCount / fillTicks))));
      angleShow(leds, data.angle, u16(cround(f(data.width * share))), data.colour, data.colour);
    } else {
      angleShow(leds, data.angle, data.width, data.backgroundColour, data.backgroundColour);
      const currentWidth = f(data.width * f(data.progress / 100));
      angleShow(leds, data.angle, u16(cround(currentWidth)), data.colour, data.colour);
    }
    return 0;
  }

  function angle(leds, clockCount, data) {
    const maxTicks = ((1 + data.repeat) * 500 + 700) / 10;
    const blank = hsv(0, 0, 0);
    if (!data.backgroundReady) return angleBackground(leds, clockCount, { ...data, colour: blank });
    angleBackground(leds, clockCount, { ...data, backgroundColour: blank });
    return clockCount > maxTicks ? 1 : 0;
  }

  function angleIntro(leds, clockCount) {
    const sequenceTicks = 36;
    if (clockCount >= sequenceTicks * 3) return 1;
    const clock = clockCount % (sequenceTicks + 1);
    const introLEDCount = 9;
    const divisor = sequenceTicks / introLEDCount;
    const progress = Math.trunc(f((introLEDCount * clock) / sequenceTicks));
    const endGap = progress + 3 - introLEDCount;
    const late = progress >= introLEDCount - 2;
    const v = progress < 3 ? 255 >> (2 - progress) : late ? 255 >> endGap : 255;
    const spin = hsv(67, 255, v);
    const tail = progress < 3 ? progress * 15 : late ? (introLEDCount - progress - 1) * 15 : 30;
    const shift = late ? endGap * 15 : 0;
    showLEDsSpin(leds, clock, divisor, 90 + shift, 0, tail, spin, spin, true);
    showLEDsSpin(leds, clock, divisor, 270 - shift, 360, tail, spin, spin, false);
    return 0;
  }

  function swipe(leds, clock, isRight, connected) {
    const swipeTicks = 20;
    const c = hsv(21, connected ? 0 : 209, 255);
    const tail = u8(f((15 * clock) / f(swipeTicks / 6)));
    showLEDsSpin(leds, clock, f(swipeTicks / 6), isRight ? 225 : 135, isRight ? 135 : 225, tail, c, c, true);
    return clock > swipeTicks ? 1 : 0;
  }

  function taps(leds, code, length, connected) {
    const c = hsv(21, connected ? 0 : 209, 255);
    for (let i = 0; i < Math.min(length, 5); i++) {
      const longTap = (code >> i) & 1;
      showArc(leds, 270 + 45 * i, 285 + 45 * i + 15 * longTap, c, c);
    }
  }

  function alarmSettingChange(leds, clockCount, enabled) {
    const growTicks = 50;
    const arcs = (clock, colour) => {
      growArc(leds, clock, f(growTicks / 8), 60, 180, colour, colour);
      growArc(leds, clock, f(growTicks / 8), 180, 300, colour, colour);
      growArc(leds, clock, f(growTicks / 8), 300, 420, colour, colour);
    };
    if (enabled) {
      if (clockCount <= growTicks) {
        arcs(clockCount, hsv(13, 207, 255));
      } else if (clockCount <= growTicks * 2) {
        const c = hsv(13, 207, f(255 - f(255 * f(f(clockCount - growTicks) / growTicks))));
        showArc(leds, 0, 360, c, c);
      } else {
        return true;
      }
      return false;
    }
    const transitionTicks = 25;
    if (clockCount <= transitionTicks) {
      const c = hsv(13, 207, f(255 * f(clockCount / transitionTicks)));
      showArc(leds, 0, 360, c, c);
    } else if (clockCount <= transitionTicks * 2) {
      const progress = f((clockCount - transitionTicks) / transitionTicks);
      const c = hsv(f(13 + f(67 * progress)), 207, 255);
      showArc(leds, 0, 360, c, c);
    } else if (clockCount <= transitionTicks * 2 + growTicks) {
      arcs(u16(growTicks - (clockCount - transitionTicks * 2)), hsv(80, 207, 255));
    } else {
      return true;
    }
    return false;
  }

  function alarmStateChange(leds, clockCount, alarmProgress) {
    const stepFlash = 50;
    const triggerLength = 1500;
    const c = hsv(13, 207, 255);
    if (alarmProgress < 100 && alarmProgress > 0) {
      if (clockCount % (stepFlash * 2)) {
        const clock = clockCount % (stepFlash * 2);
        const progress = f(0.1 + (0.9 * f(clock % stepFlash)) / stepFlash);
        showArc(leds, 0, 360, hsv(13, 207, 0), hsv(13, 207, 0));
        c.v = u8(f(clock < stepFlash ? f(255 * progress) : f(255 - f(255 * progress))));
        for (let i = 0; i <= cdiv(8 * alarmProgress, 100); i++) {
          showArc(leds, 60, 75 + i * 15, c, c);
          showArc(leds, 180, 195 + i * 15, c, c);
          showArc(leds, 300, 315 + i * 15, c, c);
        }
      }
      return clockCount >= stepFlash * 4 * 2;
    }
    if (alarmProgress !== 0 && clockCount < triggerLength) {
      const clock = clockCount % (stepFlash * 2);
      c.v = 128;
      if (clock < 2) c.s = 0;
      else if (clock > 5) c.v = 0;
      showArc(leds, 0, 360, c, c);
      return false;
    }
    c.v = 0;
    showArc(leds, 0, 360, c, c);
    return true;
  }

  function clock(leds, clockCount, data) {
    const hourAngle = cdiv(360 * (data.hour % 12), 12) + 15 * (data.minute > 32 ? 1 : 0);
    const minuteAngle = cdiv(360 * data.minute, 60);
    const angleGap = u8(Math.abs(hourAngle - minuteAngle));
    const fadeInTicks = 63;
    const fadeOutTicks = 63;
    const blinkTicks = angleGap < 15 ? 32 : 16;
    const halfOut = cdiv(fadeOutTicks, 2);
    const halfIn = cdiv(fadeInTicks, 2);
    const hourAt = (v) => ({ h: data.hourHsv.h, s: data.hourHsv.s, v: u8(v) });
    const minuteAt = (v) => ({ h: data.minuteHsv.h, s: data.minuteHsv.s, v: u8(v) });
    const hourArc = (c) => showArc(leds, hourAngle, hourAngle + 15, c, c);
    const minuteArc = (c) => showArc(leds, minuteAngle, minuteAngle + 15, c, c);

    const overlapping = Math.ceil(f(hourAngle / 15)) === Math.ceil(f(minuteAngle / 15));
    let loopClock = u16(overlapping
      ? (clockCount - fadeInTicks) % (blinkTicks * 2)
      : (clockCount - fadeInTicks) % (halfOut + blinkTicks + halfIn + blinkTicks));
    if (overlapping) loopClock = loopClock > blinkTicks ? loopClock + fadeOutTicks : loopClock + halfOut;
    const minuteFinalAngle = minuteAngle > hourAngle ? minuteAngle : minuteAngle + 360;
    const minuteSpinTicks = cdiv(2 * (minuteFinalAngle - hourAngle), 15);
    const hourSpinTicks = cdiv(2 * hourAngle, 15);

    if (data.intro && clockCount < hourSpinTicks) {
      const c = hourAt(255 * cdiv(clockCount, fadeInTicks));
      showLEDsSpin(leds, clockCount, cdiv(hourSpinTicks, cdiv(hourAngle, 15)), 0, hourAngle, 0, c, c, true);
    } else if (data.intro && clockCount <= hourSpinTicks + minuteSpinTicks) {
      const fadeIn = Math.min(f(clockCount / fadeInTicks), 1);
      const spinLeds = Math.ceil(f(((minuteAngle > hourAngle ? 0 : 360) + minuteAngle - hourAngle) / 15));
      const m = minuteAt(f(255 * fadeIn));
      showLEDsSpin(leds, clockCount - hourSpinTicks, f(minuteSpinTicks / spinLeds), hourAngle, minuteFinalAngle,
        0, m, m, true);
      hourArc(hourAt(f(255 * fadeIn)));
    } else if (clockCount < fadeInTicks) {
      const fadeIn = f(clockCount / fadeInTicks);
      hourArc(hourAt(f(255 * fadeIn)));
      minuteArc(minuteAt(f(255 * fadeIn)));
    } else if (loopClock < halfOut) {
      hourArc(hourAt(255));
      minuteArc(minuteAt(f(255 - f(255 * f(loopClock / fadeOutTicks)))));
    } else if (loopClock < halfOut + blinkTicks) {
      hourArc(hourAt(255));
      if (!overlapping) minuteArc(minuteAt(127));
    } else if (loopClock < halfOut + blinkTicks + halfIn) {
      const fadeIn = f((loopClock - (halfOut + blinkTicks)) / fadeInTicks);
      hourArc(hourAt(255));
      minuteArc(minuteAt(f(255 * f(0.5 + fadeIn))));
    } else if (loopClock < halfOut + blinkTicks + halfIn + blinkTicks) {
      hourArc(hourAt(255));
      minuteArc(minuteAt(255));
    }
    return false;
  }

  function battery(leds, clockCount, stateOfCharge) {
    const fillTicks = 50;
    const retractTicks = 50;
    const idleTicks = 200;
    const start = hsv(0, 255, 85);
    const end = hsv(85, 255, 85);
    const offLEDs = f(f(23 * (100 - stateOfCharge)) / 100);
    if (clockCount < fillTicks) {
      if (clockCount < 25) {
        growArc(leds, clockCount, f(25 / 12), 180, 396, start, end);
      } else {
        showArc(leds, 180, 375, start, end);
        growArc(leds, clockCount - 25, f(25 / 11), 15, 180, end, end);
      }
    } else if (clockCount < fillTicks + retractTicks) {
      let clk = retractTicks - (clockCount - fillTicks);
      if (offLEDs < 11) {
        const minimum = u16(f(f(retractTicks * f(11 - offLEDs)) / 11));
        clk = u8(f(f(f(clk * offLEDs) / 11) + minimum));
        showArc(leds, 180, 375, start, end);
        growArc(leds, clk, f(retractTicks / 11), 15, 180, end, end);
      } else {
        const minimum = u16(f(f(retractTicks * f(13 - f(offLEDs - 11))) / 13));
        const split = f(1 - f(11 / offLEDs));
        const firstClock = f(clk / retractTicks) < split
          ? u16(f(minimum + f(f(f(clk / split) * f(50 - minimum)) / 50))) : retractTicks;
        const secondClock = f(clk / retractTicks) > split
          ? u16(f(f(clk - f(retractTicks * split)) / f(11 / offLEDs))) : 0;
        growArc(leds, firstClock, f(retractTicks / 13), 180, 396, start, end);
        if (secondClock) growArc(leds, secondClock, f(retractTicks / 11), 15, 180, end, end);
      }
    } else if (clockCount < fillTicks + retractTicks + idleTicks) {
      if (offLEDs < 11) {
        const minimum = u16(f(f(retractTicks * f(11 - offLEDs)) / 11));
        showArc(leds, 180, 375, start, end);
        growArc(leds, minimum, f(retractTicks / 11), 15, 180, end, end);
      } else {
        const minimum = u16(f(f(retractTicks * f(13 - f(offLEDs - 11))) / 13));
        growArc(leds, minimum, f(retractTicks / 13), 180, 396, start, end);
      }
    } else if (clockCount > fillTicks + retractTicks + idleTicks) {
      return 1;
    }
    return 0;
  }

  const SHFirmware = {
    LED_COUNT, RGB_LED_COUNT, hsv, hsvToRgb, showArc, logo, disconnect, pointer, speedometer, angleShow,
    angleBackground, angle, angleIntro, swipe, taps, alarmSettingChange, alarmStateChange, clock, battery,
  };
  if (typeof module !== 'undefined') module.exports = SHFirmware;
  else root.SHFirmware = SHFirmware;
})(this);
