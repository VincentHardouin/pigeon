# Battery: BLE sync vs Wi-Fi left on

Is syncing over BLE (Bluetooth on for a few seconds per sync, then off) cheaper than leaving Wi-Fi on while reading so `cwasync` can sync directly?

## Results

PocketBook Verse Pro, 18 November 2026, screen awake on one page, frontlight off, no page turns.

| State | Avg current | Over baseline |
|---|---|---|
| `baseline`: Wi-Fi and Bluetooth off | 82.2 mA | |
| `wifi`: Wi-Fi on, connected, idle | 98.1 mA | +15.9 mA |
| `bluetooth`: Bluetooth on, idle | 85.2 mA | +3.0 mA |
| `sync`: one BLE sync, Bluetooth on to off | 101.1 mA for 31 s | +18.9 mA for 31 s ≈ 0.16 mAh |

- **Wi-Fi left on costs about 16 mAh per hour of reading**, about 19 % more than the baseline draw.
- **BLE sync costs about 0.5 mAh per hour** at 3 syncs an hour (one page a minute, a sync every 20 pages): about 30 times less, under 1 % of the baseline draw.

`current_now` is the fuel gauge's smoothed reading and only changes about every 20 s, so these are orders of magnitude, not precise figures. They come from a single run of each state.

## Reproduce

1. On the e-reader: KOReader auto-sleep off (nothing runs while it sleeps), frontlight off, a book open, Wi-Fi and KOReader's SSH server on.
2. Copy and start the test detached. It takes about 4 minutes; it turns Wi-Fi off for the middle part, then back on.

   ```sh
   ssh -p 2221 reader@<e-reader> 'cat > /mnt/ext1/applications/power-test.sh' < tools/power-test.sh
   ssh -p 2221 reader@<e-reader> 'nohup sh /mnt/ext1/applications/power-test.sh > /dev/null 2>&1 < /dev/null &'
   ```

3. Once Wi-Fi is back, read `/mnt/ext1/applications/power.log.summary`. `power.log` holds one sample a second: `state,epoch,current_now (µA, negative while discharging)`.

The `sync` state sends a copy of the plugin's outbox, so the iPhone app must be in the background nearby; the plugin's own queue is left alone.
