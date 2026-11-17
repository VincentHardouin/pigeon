#!/bin/sh
# Phase 0, test 3: one ~250-byte write from the PocketBook to LightBlue (char 0x2222).
/ebrmain/bin/netagent bt on >/dev/null 2>&1
sleep 8

P='{"v":1,"document":"9e107d9d372bb6826bd81d3542a419d6","progress":"/body/DocFragment[12]/body/div/p[34]/text().56","percentage":0.4567,"device":"PocketBook Verse Pro","device_id":"0123456789abcdef0123456789abcdef","captured_at":1794680000,"sent_at":1794680582}'
HEX=$(printf %s "$P" | hexdump -v -e '/1 "0x%02x "' | sed 's/ *$//')
echo "taille: ${#P} octets, hex: $(echo "$HEX" | wc -w) octets"
[ -n "$HEX" ] || { echo "conversion hex impossible"; /ebrmain/bin/netagent bt off >/dev/null 2>&1; exit 1; }

(echo "scan on"; sleep 10; echo "scan off"; echo "quit") | bluetoothctl > /tmp/scan.log 2>&1
# LightBlue's service UUID is not in its adverts: pick the most active device, which was the iPhone in earlier tests.
ADDR=$(grep -oE 'Device ([0-9A-F]{2}:){5}[0-9A-F]{2}' /tmp/scan.log | sort | uniq -c | sort -rn | head -1 | grep -oE '([0-9A-F]{2}:){5}[0-9A-F]{2}')
echo "ADDR=$ADDR"

(echo "scan on"; sleep 5; echo "connect $ADDR"; sleep 8; echo "scan off"
 echo "menu gatt"; echo "select-attribute 00002222-0000-1000-8000-00805f9b34fb"
 echo "write \"$HEX\""; sleep 4; echo "back"
 echo "disconnect $ADDR"; sleep 2; echo "quit") | bluetoothctl > /tmp/bt.log 2>&1
grep -v ManufacturerData /tmp/bt.log | grep -iE 'attempting|failed|successful|name:'

/ebrmain/bin/netagent bt off >/dev/null 2>&1
echo fin
