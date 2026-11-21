# PocketBook Bluetooth findings

Tested on real hardware in November 2026. These results shaped the design; there is no need to test them again.

## Device

- PocketBook Verse Pro, KOReader, Linux 3.10.65 (armv7l), Realtek Bluetooth 4.2 chip, BlueZ 5.52.
- KOReader runs as `reader` (uid 101), **not root**. The D-Bus policy lets `reader` talk to `org.bluez`.
- Available tools: `bluetoothctl`, `gatttool`, `hciconfig`, `hcitool`, `dbus-send`. BusyBox has no `od -An -tx1`: use `hexdump -v -e '/1 "%02x"'`.
- `/ebrmain/bin/netagent bt on|off` turns Bluetooth fully on and off as `reader` (`bt off` stops `bluetoothd` and the chip). `bluetoothctl power` only toggles the radio.
- Nothing runs during sleep: the device effectively powers off.

## What works

- BLE scan, connection to the iPhone's current random address, GATT discovery, read and write.
- Long writes: 258 bytes arrive whole in one write, no chunking needed on the e-reader side.
- `gatttool` writes without triggering a pairing prompt on the iPhone. `bluetoothctl` connects through `bluetoothd`, whose GATT client reads the iPhone's encrypted services and makes it ask to pair on every sync.

## What does not

| Attempt | Result | Cause |
|---|---|---|
| Advertising (`advertise on`) | `NotPermitted` | `SupportedInstances = 0`: kernel 3.10 predates the advertising API (Linux 4.1) |
| Being visible to an iPhone | Not found by CoreBluetooth | Only visible over Bluetooth Classic |
| Bluetooth tethering (PAN/NAP) | No `org.bluez.Network1` | BlueZ built without the network plugin |
| LE-only scan (`SetDiscoveryFilter`) | `NotSupported` | Kernel too old |
| Reconnecting to a bonded iPhone by identity address | `Failed` | No resolution of the iPhone's rotating private addresses (no IRK support) |

## Consequences for the design

- The e-reader must be the central and **find the iPhone by scanning on every sync**: its address changes about every 15 minutes.
- iOS uses a separate random address per advertising set, so the "Apple" address seen in a scan may not be the app's.
- In the foreground the app advertises the name `Pigeon`, which `bluetoothctl` shows. In the background iOS drops the name and hides the service UUID in its overflow area (Apple manufacturer data `0x004C`). The sender then tries the last working address, then Apple devices ranked by how often they were seen, and keeps the first one exposing the service.
- The overflow area is visible to the e-reader: `bluetoothctl` prints it as Apple manufacturer data starting with `01`, followed by a 128-bit bitmap. The Pigeon service sets `0x20` in the 10th byte of that value (observed 21 November 2026, iPhone locked), so the sender targets that bit first.
- BusyBox `sed` does not understand `\x1b`: `bluetoothctl` output keeps its colour codes and prompt, redrawn after a `\r` on every line.
- Pairing brings nothing: without address resolution a bond is never reused.
