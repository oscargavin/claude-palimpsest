#!/bin/bash
# Sound notification for Claude Code
# Called by Notification hook — plays tap_01 sound
# Cross-platform: macOS (afplay), PulseAudio (paplay), ALSA (aplay)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SOUND="$PLUGIN_ROOT/sounds/tap_01.wav"

if command -v afplay >/dev/null 2>&1; then
  afplay "$SOUND" &
elif command -v paplay >/dev/null 2>&1; then
  paplay "$SOUND" &
elif command -v aplay >/dev/null 2>&1; then
  aplay "$SOUND" &
fi

exit 0
