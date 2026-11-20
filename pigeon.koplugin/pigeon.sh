#!/bin/sh
# Sends every line of outbox.jsonl to the iOS app over BLE, then writes status:
# "OK" or "FAIL", followed by one "OK <document> <captured_at>" line per delivered entry.
# Usage: pigeon.sh <plugin dir>
DIR=$1
OUTBOX=$DIR/outbox.jsonl
LOG=$DIR/sync.log
LAST_ADDR_FILE=$DIR/last_addr
STATUS=$DIR/status
HISTORY=$DIR/history.log
SERVICE=947694fe-0425-4e30-84bc-fb783e781ead
CHAR=1fd42b59-27a4-49f9-b36b-c1d0f9c445b2
LOCK=/tmp/pigeon.pid

[ -s "$OUTBOX" ] || exit 0
if [ -f $LOCK ] && kill -0 "$(cat $LOCK)" 2>/dev/null; then exit 0; fi
echo $$ > $LOCK
# sync.log only holds the last run: keep the previous ones to diagnose a failure after the fact.
trap 'cat "$LOG" >> "$HISTORY"; tail -n 300 "$HISTORY" > "$HISTORY.tmp" && mv "$HISTORY.tmp" "$HISTORY"; rm -f $LOCK' EXIT
# The plugin may rewrite the outbox mid-run: work on a snapshot so status only lists what was really sent.
cp "$OUTBOX" /tmp/pigeon-outbox.jsonl
OUTBOX=/tmp/pigeon-outbox.jsonl

exec > "$LOG" 2>&1
log() { echo "$(date +%H:%M:%S) $*"; }

# Leave Bluetooth as the user had it.
if ps | grep -q '[b]luetoothd'; then WAS_ON=1; else WAS_ON=0; /ebrmain/bin/netagent bt on; sleep 8; fi
bt_restore() { [ $WAS_ON = 1 ] || /ebrmain/bin/netagent bt off; }

(echo "scan on"; sleep 10; echo "scan off"; echo "devices"; echo "quit") | bluetoothctl 2>&1 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' > /tmp/pigeon-scan.log
ADDR_RE='([0-9A-F]{2}:){5}[0-9A-F]{2}'
# Order: the app advertising under its own name (foreground), last iPhone that worked, then Apple devices by activity.
# ponytail: activity count stands in for RSSI, which bluetoothctl reports too sparsely to rank on.
# bluetoothctl never prints the advertised service UUIDs of a newly found device, only its name.
APP=$(grep -E "Device $ADDR_RE Pigeon" /tmp/pigeon-scan.log | grep -oE "$ADDR_RE")
LAST=$(cat "$LAST_ADDR_FILE" 2>/dev/null)
grep -q "$LAST" /tmp/pigeon-scan.log 2>/dev/null || LAST=
APPLE=$(grep -i 'ManufacturerData Key: 0x004c' /tmp/pigeon-scan.log | grep -oE "$ADDR_RE" | sort -u)
RANKED=$(for a in $APPLE; do echo "$(grep -c "$a" /tmp/pigeon-scan.log) $a"; done | sort -rn | head -5 | cut -d' ' -f2)
CANDIDATES=$(for a in $APP $LAST $RANKED; do echo $a; done | awk '!seen[$0]++')
log "candidats: $(echo $CANDIDATES)"

# gatttool talks ATT directly: bluetoothd's own GATT client would read encrypted iPhone services
# (battery, device info) and make the iPhone ask to pair on every sync.
send_to() {
    H=$(timeout 25 gatttool -t random -b "$1" --characteristics --uuid=$CHAR 2>&1 | sed -n 's/.*char value handle = \(0x[0-9a-f]*\).*/\1/p')
    [ -n "$H" ] || { echo "pas d'app Pigeon"; return 1; }
    while read -r line; do
        msg=$(echo "$line" | sed "s/}\$/,\"sent_at\":$(date +%s)}/")
        out=$(timeout 25 gatttool -t random -b "$1" --char-write-req -a "$H" -n "$(printf %s "$msg" | hexdump -v -e '/1 "%02x"')" 2>&1)
        echo "$out"
        echo "$out" | grep -q 'written successfully' || return 1
    done < "$OUTBOX"
}

for a in $CANDIDATES; do
    log "essai $a"
    if send_to "$a"; then
        echo "$a" > "$LAST_ADDR_FILE"
        log "OK $(grep -c . "$OUTBOX") envoi(s) vers $a"
        # Written then renamed: the plugin polls this file and must never read it half-written.
        { echo OK; sed 's/.*"document":"\([^"]*\)".*"captured_at":\([0-9]*\).*/OK \1 \2/' "$OUTBOX"; } > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
        bt_restore
        exit 0
    fi
done
log "ECHEC : iPhone introuvable"
echo FAIL > "$STATUS"
bt_restore
