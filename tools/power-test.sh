#!/bin/sh
# Measures the e-reader's battery current with Wi-Fi on, everything off, Bluetooth idle, and during one BLE sync.
# Takes about 5 minutes. Start it detached over SSH: it turns Wi-Fi off for the middle part, then back on.
# The screen must stay awake (KOReader auto-sleep off): nothing runs while the e-reader sleeps.
# Usage: power-test.sh [seconds per state]   Results: power.log next to this script, summary at the end.
S=${1:-60}
P=/mnt/ext1/applications/koreader/plugins/blesync.koplugin
NET=/ebrmain/bin/netagent
OUT=$(dirname "$0")/power.log
for d in /sys/class/power_supply/*; do [ "$(cat "$d/type")" = Battery ] && B=$d; done
: > "$OUT"

sample() { echo "$1,$(date +%s),$(cat "$B/current_now")" >> "$OUT"; sleep 1; }
measure() { end=$(( $(date +%s) + $2 )); while [ "$(date +%s)" -lt "$end" ]; do sample "$1"; done; }

$NET bt off
measure wifi "$S"
$NET net off; sleep 15
measure baseline "$S"
$NET bt on; sleep 10
measure bluetooth "$S"
$NET bt off; sleep 10
# A copy of the outbox, so the plugin's own queue and status file are left alone.
mkdir -p /tmp/bs && cp "$P/outbox.jsonl" "$P/last_addr" /tmp/bs/ 2>/dev/null
sh "$P/blesync.sh" /tmp/bs & pid=$!
while kill -0 $pid 2>/dev/null; do sample sync; done
$NET net on

# current_now is in µA, negative while discharging.
awk -F, '{ n[$1]++; i[$1] -= $3; if (!($1 in t0)) t0[$1] = $2; t1[$1] = $2 }
  END { for (l in n) printf "%-10s %6.1f mA over %d s\n", l, i[l] / n[l] / 1000, t1[l] - t0[l] + 1 }' "$OUT" > "$OUT.summary"
tail -1 /tmp/bs/sync.log >> "$OUT.summary"
