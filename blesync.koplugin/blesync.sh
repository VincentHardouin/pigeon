#!/bin/sh
# Sends every line of outbox.jsonl to the iOS app over BLE, then writes "OK <document> <captured_at>" lines to result.txt.
# Usage: blesync.sh <plugin dir>
DIR=$1
OUTBOX=$DIR/outbox.jsonl
RESULT=$DIR/result.txt
LOG=$DIR/sync.log
LAST_ADDR_FILE=$DIR/last_addr
STATUS=$DIR/status.txt
SERVICE=947694fe-0425-4e30-84bc-fb783e781ead
CHAR=1fd42b59-27a4-49f9-b36b-c1d0f9c445b2
LOCK=/tmp/blesync.pid

[ -s "$OUTBOX" ] || exit 0
if [ -f $LOCK ] && kill -0 "$(cat $LOCK)" 2>/dev/null; then exit 0; fi
echo $$ > $LOCK
trap 'rm -f $LOCK' EXIT
# The plugin may rewrite the outbox mid-run: work on a snapshot so result.txt only lists what was really sent.
cp "$OUTBOX" /tmp/blesync-outbox.jsonl
OUTBOX=/tmp/blesync-outbox.jsonl

exec > "$LOG" 2>&1
log() { echo "$(date +%H:%M:%S) $*"; }

# Leave Bluetooth as the user had it.
if ps | grep -q '[b]luetoothd'; then WAS_ON=1; else WAS_ON=0; /ebrmain/bin/netagent bt on; sleep 8; fi
bt_restore() { [ $WAS_ON = 1 ] || /ebrmain/bin/netagent bt off; }

(echo "scan on"; sleep 10; echo "scan off"; echo "devices"; echo "quit") | bluetoothctl 2>&1 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' > /tmp/blesync-scan.log
ADDR_RE='([0-9A-F]{2}:){5}[0-9A-F]{2}'
# Order: the app advertising under its own name (foreground), last iPhone that worked, then Apple devices by activity.
# ponytail: activity count stands in for RSSI, which bluetoothctl reports too sparsely to rank on.
# bluetoothctl never prints the advertised service UUIDs of a newly found device, only its name.
APP=$(grep -E "Device $ADDR_RE BLESync" /tmp/blesync-scan.log | grep -oE "$ADDR_RE")
LAST=$(cat "$LAST_ADDR_FILE" 2>/dev/null)
grep -q "$LAST" /tmp/blesync-scan.log 2>/dev/null || LAST=
APPLE=$(grep -i 'ManufacturerData Key: 0x004c' /tmp/blesync-scan.log | grep -oE "$ADDR_RE" | sort -u)
RANKED=$(for a in $APPLE; do echo "$(grep -c "$a" /tmp/blesync-scan.log) $a"; done | sort -rn | head -5 | cut -d' ' -f2)
CANDIDATES=$(for a in $APP $LAST $RANKED; do echo $a; done | awk '!seen[$0]++')
log "candidats: $(echo $CANDIDATES)"

# gatttool talks ATT directly: bluetoothd's own GATT client would read encrypted iPhone services
# (battery, device info) and make the iPhone ask to pair on every sync.
send_to() {
    H=$(timeout 25 gatttool -t random -b "$1" --characteristics --uuid=$CHAR 2>&1 | sed -n 's/.*char value handle = \(0x[0-9a-f]*\).*/\1/p')
    [ -n "$H" ] || { echo "pas d'app BLESync"; return 1; }
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
        sed 's/.*"document":"\([^"]*\)".*"captured_at":\([0-9]*\).*/OK \1 \2/' "$OUTBOX" > "$RESULT"
        log "OK $(grep -c . "$RESULT") envoi(s) vers $a"
        echo OK > "$STATUS"
        bt_restore
        exit 0
    fi
done
log "ECHEC : iPhone introuvable"
echo FAIL > "$STATUS"
bt_restore
