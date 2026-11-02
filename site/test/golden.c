// Runs the original firmware animations over a table of scenarios and prints every frame.
#include <AnimationsLibrary.h>
#include <string.h>

static uint8_t leds[512];

static void frame(const char *name, int t, int ret) {
    printf("%s %d %d ", name, t, ret);
    for (int i = 0; i < 72; i++) printf("%02x", leds[i]);
    putchar('\n');
}

#define RUN(name, n, call) \
    for (int t = 0; t < (n); t++) { memset(leds, 0, sizeof(leds)); int r = (call); frame(name, t, r != 0); }

int main(void) {
    HsvColour_t green = {67, 255, 255}, orange = {30, 255, 255}, white = {0, 0, 255};
    HsvColour_t call = {143, 219, 198}, rain = {170, 220, 255}, blank = {0, 0, 0};
    RUN("logo", 340, logo_AnimationsLibrary(leds, t))
    RUN("disconnect", 170, disconnect_AnimationsLibrary(leds, t))

    struct PointerAnimationData p[] = {
        {.heading = 90, .colour = green},
        {.heading = 65416, .headingGap = 40, .colour = orange},
        {.heading = 12, .headingGap = 200, .colour = green},
        {.heading = 300, .headingGap = -200, .colour = green},
        {.heading = 0, .colour = {17, 255, 255}, .standby = true},
        {.heading = 45, .colour = orange, .off = true},
    };
    for (int i = 0; i < 6; i++) { char n[16]; sprintf(n, "pointer%d", i); RUN(n, 200, pointer_AnimationsLibrary(leds, t, &p[i])) }

    struct SpeedometerAnimationData s[] = {{.percentage = 62, .gap = 20}, {.percentage = 0}, {.percentage = 100, .gap = -10}};
    for (int i = 0; i < 3; i++) { char n[16]; sprintf(n, "speed%d", i); RUN(n, 90, speedometer_AnimationsLibrary(leds, t, &s[i])) }

    struct AngleAnimationData a[] = {
        {.colour = green, .angle = 90, .progress = 0, .width = 105, .backgroundColour = white},
        {.colour = green, .angle = 90, .progress = 40, .gap = 20, .width = 105, .backgroundColour = white, .backgroundReady = true},
        {.colour = green, .angle = -90, .progress = 70, .gap = 5, .width = 105, .backgroundColour = white, .backgroundReady = true},
        {.colour = green, .angle = 37, .progress = 100, .gap = 18, .width = 105, .backgroundColour = white, .backgroundReady = true},
        {.colour = green, .angle = 90, .progress = 100, .gap = 0, .width = 105, .backgroundColour = white, .backgroundReady = true},
        {.colour = green, .angle = 0, .progress = 100, .gap = 100, .width = 360, .backgroundColour = white, .backgroundReady = true},
        {.colour = green, .angle = 0, .progress = 0, .width = 360, .backgroundColour = white},
    };
    for (int i = 0; i < 7; i++) { char n[16]; sprintf(n, "bg%d", i); RUN(n, 170, angleBackground_AnimationsLibrary(leds, t, &a[i])) }

    struct AngleAnimationData notify[] = {
        {.colour = call, .progress = 100, .gap = 100, .width = 360, .repeat = 60, .backgroundReady = true},
        {.colour = rain, .progress = 100, .gap = 100, .width = 360, .repeat = 10, .backgroundReady = true},
    };
    for (int i = 0; i < 2; i++) { char n[16]; sprintf(n, "notify%d", i); RUN(n, 700, angle_AnimationsLibrary(leds, t, &notify[i])) }

    RUN("intro", 120, angleIntro_AnimationsLibrary(leds, t))
    RUN("swipeR", 26, swipe_AnimationsLibrary(leds, t, true, true))
    RUN("swipeL", 26, swipe_AnimationsLibrary(leds, t, false, true))
    for (int len = 1; len <= 5; len++) { char n[16]; sprintf(n, "taps%d", len); RUN(n, 1, (taps_AnimationsLibrary(leds, t, 0x0a, len, true, StandbyOff, false), 0)) }
    RUN("armOn", 120, alarmSettingChange_AnimationsLibrary(leds, t, true))
    RUN("armOff", 120, alarmSettingChange_AnimationsLibrary(leds, t, false))
    uint8_t levels[] = {33, 66, 100, 0}, front;
    for (int i = 0; i < 4; i++) { char n[16]; sprintf(n, "alarm%d", levels[i]); RUN(n, 460, alarmStateChange_AnimationsLibrary(leds, t, levels[i], &front)) }

    struct ClockAnimationData c[] = {
        {.hour = 10, .minute = 10, .hourHsv = {0, 0, 220}, .minuteHsv = {143, 219, 198}, .duration = -1, .intro = true},
        {.hour = 4, .minute = 22, .hourHsv = {0, 0, 220}, .minuteHsv = {143, 219, 198}, .duration = -1},
        {.hour = 3, .minute = 16, .hourHsv = {0, 0, 220}, .minuteHsv = {143, 219, 198}, .duration = -1},
        {.hour = 7, .minute = 40, .hourHsv = {0, 0, 220}, .minuteHsv = {143, 219, 198}, .duration = -1, .intro = true},
    };
    for (int i = 0; i < 4; i++) { char n[16]; sprintf(n, "clock%d", i); RUN(n, 420, clock_AnimationsLibrary(leds, t, &c[i])) }

    uint8_t charge[] = {80, 30, 100, 5};
    for (int i = 0; i < 4; i++) {
        struct StateOfChargeAnimationData b = {.stateOfCharge = charge[i]};
        char n[16]; sprintf(n, "battery%d", charge[i]);
        RUN(n, 310, battery_AnimationsLibrary(leds, t, &b))
    }
    return 0;
}
