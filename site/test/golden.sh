#!/usr/bin/env bash
# Compares firmware.js with the original C, frame by frame. Needs reference/smarthalo-firmware.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fw=$here/../../reference/smarthalo-firmware/smart_halo-smarthalo2-stm-firmware-b172e75c4188
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

cp "$fw/Src/SmartHaloOS/AnimationsLibrary.c" "$fw/Inc/SmartHaloOS/AnimationsLibrary.h" "$here/golden.c" "$build/"
for h in FreeRTOS task FreeRTOSConfig queue semphr cmsis_os reboot; do : > "$build/$h.h"; done
cat > "$build/Shell.h" <<'H'
#define log_Shell(...) ((void)0)
#define soft_crash(x) ((void)0)
#define eANIMATIONSLIBRARY 0
H
cat > "$build/GraphicsTask.h" <<'H'
#include <stdint.h>
#include <stdbool.h>
#define MAX_LED_BRIGHTNESS 255
#define MIN_LED_BRIGHTNESS 120
#define MAX_ANGLES 8
typedef struct { uint8_t r, g, b; } RgbColour_t;
typedef struct { uint8_t h, s, v; } HsvColour_t;
struct FrontLightAnimationData { uint8_t percentage; int8_t gap; bool isBlinking; };
H
cat > "$build/CommunicationTask.h" <<'H'
typedef enum { StandbyOff = 0, StandbySleep = 254, StandbyArmed = 255 } eStandbyReason_t;
H

gcc -std=gnu11 -O1 -w -include string.h -I"$build" "$build/golden.c" "$build/AnimationsLibrary.c" -lm -o "$build/golden"
"$build/golden" > "$build/c.txt"
node "$here/golden.js" > "$build/js.txt"

total=$(wc -l < "$build/c.txt")
if cmp -s "$build/c.txt" "$build/js.txt"; then
  echo "OK: $total frames identical to the firmware C"
else
  paste -d'\n' "$build/c.txt" "$build/js.txt" | awk 'NR%2{a=$0;next} a!=$0{split(a,p," ");n[p[1]]++;t++} END{for(k in n)print k, n[k]; print "different frames:", t+0}' | sort
  echo "of $total frames"
  exit 1
fi
