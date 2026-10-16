# btcclock

Live Bitcoin network data as BTClock-style e-paper panels: block height, price, Moscow time, fees, halving and supply. Data comes from mempool.space's public API.

## Using it

The tile rotates through the fields you enable every 15 seconds. Tap the large e-paper panels to switch to the next field, and tap the header row (the label and the `n/total` counter) to open the full-screen view.

In the full-screen view, the **fields** tab lists the fields that have loaded, and the **config** tab turns fields on or off and reorders the ones that are on. The order is saved on the device.

## Update notes — 1.3

- The fees field now shows all three rates (economy / half-hour / fastest, e.g. `1/1/1`) instead of only the half-hour fee.
- One press on the panels switches to the next field; the header row opens the full-screen fields/config view. A widget can't capture a long press — the home screen uses it to move and resize tiles — so the top bar is the way into the menu.
- Field rotation is now every 15 seconds (was 20).

## Source

- [mempool.space API](https://mempool.space/docs/api/rest)
