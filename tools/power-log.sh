#!/bin/sh
# Logs battery readings every 10 s, to compare the e-reader's power draw with Wi-Fi on, Bluetooth on, or both off.
# Usage: power-log.sh <label> [minutes] [output]   (30 minutes and power.log next to this script by default)
# The screen must stay awake for the whole run: nothing runs while the e-reader sleeps.
LABEL=${1:?label required}
MINUTES=${2:-30}
OUT=${3:-$(dirname "$0")/power.log}

for d in /sys/class/power_supply/*; do
    [ "$(cat "$d/type" 2>/dev/null)" = Battery ] && BAT=$d && break
done
[ -n "$BAT" ] || { echo "no battery under /sys/class/power_supply" >&2; exit 1; }

# Missing attributes stay empty: some drivers only expose capacity.
attr() { cat "$BAT/$1" 2>/dev/null; }
END=$(( $(date +%s) + MINUTES * 60 ))
while [ "$(date +%s)" -lt $END ]; do
    echo "$(date +%s),$LABEL,$(attr capacity),$(attr voltage_now),$(attr current_now)" >> "$OUT"
    sleep 10
done
