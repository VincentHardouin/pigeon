# Battery: BLE sync vs Wi-Fi left on

**Status: not measured yet.** This page holds the protocol; results go in the table below.

## Question

Is syncing over BLE (Bluetooth on for about 15 s per sync, then off) cheaper than leaving Wi-Fi on while reading so `cwasync` can sync directly?

## Protocol

1. Copy `tools/power-log.sh` to the e-reader (for example `/mnt/ext1/applications/`).
2. Same conditions for every run: frontlight off, same book, same page, no page turns (e-ink refreshes would dominate), KOReader auto-sleep disabled so the screen stays awake.
3. Run each scenario for 30 minutes, each with its own label. Start the logger over SSH with `nohup`, then set the radios from KOReader:

   ```sh
   nohup sh /mnt/ext1/applications/power-log.sh baseline 30 > /dev/null 2>&1 &
   ```

   | Label | Wi-Fi | Bluetooth |
   |---|---|---|
   | `baseline` | off | off |
   | `wifi` | on, connected | off |
   | `bluetooth` | off | on, idle (`/ebrmain/bin/netagent bt on`) |
   | `sync` | off | **Sync now** once a minute |

4. Copy `power.log` back and summarise each scenario:

   ```sh
   awk -F, '{ n[$2]++; i[$2]+=$5; if (!($2 in t0)) { t0[$2]=$1; c0[$2]=$3 } t1[$2]=$1; c1[$2]=$3 }
     END { for (l in n) printf "%-10s avg current %6.1f mA, %4.1f %%/h\n", l, i[l]/n[l]/1000,
           (c0[l]-c1[l]) * 3600 / (t1[l]-t0[l]) }' power.log
   ```

If the driver does not expose `current_now`, only the capacity drop is available. It moves in 1 % steps, so run each scenario for at least 2 hours instead.

## Reading the results

- Cost of Wi-Fi left on: `wifi − baseline`, all the time the book is open.
- Cost of BLE sync: the `sync` run does one sync a minute, so the cost for N syncs an hour is `(sync − baseline) × N / 60`. At one page a minute and a sync every 20 pages, N is 3.

## Results

| Scenario | Avg current | Battery per hour |
|---|---|---|
| `baseline` | | |
| `wifi` | | |
| `bluetooth` | | |
| `sync` | | |
