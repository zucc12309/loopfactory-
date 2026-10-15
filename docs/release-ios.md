# iOS release

This page used to hold the iOS readiness notes. They now live in:

* [IOS_READINESS.md](IOS_READINESS.md): status, compatibility matrix, architecture, evidence and
  blockers.
* [IOS_BUILD_RUNBOOK.md](IOS_BUILD_RUNBOOK.md): exact Mac steps for the Simulator, your iPhone,
  staging/production archives and Universal Links.
* [IOS_DEVICE_TEST_MATRIX.md](IOS_DEVICE_TEST_MATRIX.md): what to test on which iPhones, with an
  evidence level for every row.

App Store submission is out of scope for now. Before it happens:
* Apple Developer Program membership, App Store Connect record, and privacy "nutrition label" from
  the data inventory in IOS_READINESS.md §8.
* Real privacy policy and support URLs (the release config refuses placeholders).
* If third-party sign-in (Google) is ever offered for account linking, App Store Review Guideline
  4.8 requires an equivalent privacy-preserving option, such as **Sign in with Apple**. The backend
  already verifies Apple ID tokens (`APPLE_BUNDLE_IDS`); no client sign-in is shipped on any
  platform.
* StoreKit is not integrated (no purchases are offered).
