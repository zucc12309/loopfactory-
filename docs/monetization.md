# Monetization (player-friendly)

Rules: no energy, no forced waiting, no interstitial between every level, nothing pay-to-win,
puzzles never locked behind payment in the core campaign.

| Product (`PRODUCTS` in services/api/src/services/purchases.ts) | Type | Grants |
|---|---|---|
| `remove_ads` | non-consumable | hides optional ad offers |
| `theme_night_shift`, `theme_sakura` | non-consumable | cosmetic themes |
| `pack_monsoon` | non-consumable | an extra curated puzzle collection |

Optional rewarded ads (remote-config flag `rewardedAdsEnabled`, default **off**) may offer an
early theme unlock; never required for hints or progression.

## Architecture
1. Client starts the purchase with the official store SDK (Google Play Billing via the
   `GodotGooglePlayBilling` plugin; StoreKit 2 plugin on iOS). No payment data touches our code.
2. Client sends the purchase token/transaction to `POST /api/v1/purchases/verify`.
3. Server verifies with the store, stores `purchase_entitlements (store, transaction_id unique)`,
   and returns active entitlements. `GET /purchases/entitlements` restores on new devices.
4. Refunds/revocations: Google RTDN and App Store Server Notifications V2 webhooks mark rows
   `refunded`/`revoked`.

## Status — pending store credentials
* ✔ Server abstraction, entitlement table, idempotent verification, cross-account protection,
  restore endpoint, dev verifier with tests.
* ◻ Google Play verifier: needs a Play Console app, service account with Android Publisher API,
  `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, package name; then implement `purchases.products.get`.
* ◻ App Store verifier: needs App Store Connect API key (issuer id, key id, private key).
* ◻ RTDN / App Store notification webhook endpoints.
* ◻ Client billing plugins and a store UI (themes screen). The client currently ships no store UI.
* ◻ Rewarded ads SDK (e.g. AdMob) — requires an ad account, consent (UMP) and is off by default.
