# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Sale Scout is a price-tracking app with two independently-deployed halves:

- **Flutter client** (repo root, `lib/`) — built and served as a **web PWA**. Deployed to Firebase Hosting (project `sale-scout-ff2a5`, live at https://sale-scout-ff2a5.web.app).
- **Node/Express scraper API** (`sale_scout_api/`) — a separate service deployed to Render at `https://sale-scout-api.onrender.com`. This base URL is **hardcoded** in `lib/main.dart`; there is no env/config indirection on the client side.

The two communicate over plain HTTP GET requests. The client owns all state (in Firestore); the API is stateless except for sending FCM pushes.

## Commands

### Flutter client (run from repo root)
```bash
flutter pub get                        # install dependencies
flutter run -d chrome                  # run locally (web is the real target — see Gotchas)
flutter analyze                        # lint (uses flutter_lints via analysis_options.yaml)
flutter test                           # run all tests
flutter test test/widget_test.dart    # run a single test file
flutter build web                      # produce build/web/ for hosting
firebase deploy --only hosting         # deploy build/web/ to Firebase Hosting
```

### Scraper API (run from `sale_scout_api/`)
```bash
npm install     # also runs postinstall → playwright install chromium
npm start       # node server.js, listens on PORT (default 3000)
```
The API requires these env vars: `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` (firebase-admin, for FCM pushes) and `SERPAPI_KEY` (Google Shopping search). There is no `.env` loader — set them in the environment / Render dashboard.

## Architecture

### Data flow for tracking an item
1. User pastes a product URL in the client. `getProductFromApi()` calls `GET /product?url=...`.
2. The API routes by URL substring: `nike.com` → `scrapeNike()` (Playwright/Chromium headless scrape of OG tags + price regex), `target.com` → `scrapeTarget()` (calls Target's internal **RedSky** JSON API by extracting the TCIN from the URL). Other retailers are rejected. Both scrapers **never throw** — on failure they return a stub object with `currentPrice: 0` and a `*_failed` source, which the client then rejects.
3. The client then calls `GET /search-deals?q=<title sku>` to find cross-retailer prices via SerpAPI Google Shopping. This is where the bulk of the API's logic lives: `smartMatchConfidence()` scores each result (SKU match, brand/model keywords, penalties for used/kids/refurbished), results are deduped to one-per-retailer (`normalizeRetailerSource`/`cleanRetailerDisplayName`), filtered by confidence + suspicious-price heuristics, and annotated with `verificationSignals` (positive/warnings) shown in the UI.
4. The assembled `ProductItem` (with appended `priceHistory` entry and `dealResults`) is stored in Firestore.

### Client state model
- **Auth + persistence is entirely Firebase.** Email/password via `firebase_auth`; per-user document at `users/{uid}` in Firestore holds `plan`, `itemLimit`, `trackedItems` (serialized `ProductItem` list), `alertHistory`, and FCM tokens. There is no backend DB — the Flutter app reads/writes Firestore directly.
- `ProductItem` and `DealResult` (in `lib/main.dart`) are the core models; both have hand-written `toJson`/`fromJson` that defensively coerce types because scraped data is unreliable. `priceHistory` is a list of `{price, timestamp}` maps used to drive `fl_chart` graphs and the "% above/below average" insights.
- **Auto-scan loop:** `startMonitoring()` runs a 1-second `Timer.periodic` counting down from 3600; on zero it calls `refreshPrices(autoScan: true)`, which re-scans every tracked item sequentially (with a 3s delay between items to avoid hammering the scraper).

### Price-drop notifications (two parallel mechanisms)
1. **Browser Notification API** (`dart:html`) — fired client-side immediately when a drop is detected.
2. **FCM push** — client stores the device token at `users/{uid}.lastFcmToken`, then on a detected drop calls `GET /send-price-drop-push?token=...` so the API sends a push via firebase-admin (works even when the tab is closed). The "prevent duplicate notifications" logic is recent (see git history) — be careful editing the drop-detection / alert-dedup path.

## Gotchas

- **The Flutter app is web-only despite the `android/`, `ios/`, `macos/`, etc. folders.** `lib/main.dart` imports `dart:html` and the FCM/notification flow assumes a browser. Don't assume mobile builds work.
- **`firebase_messaging` is imported in `lib/main.dart` but is NOT listed in `pubspec.yaml`.** If a clean `flutter pub get` / build fails on a missing `firebase_messaging`, that dependency needs adding — confirm against the deployed build before changing it.
- **`lib/mainold.dart` is dead code** — a previous version kept for reference. The live entrypoint is `lib/main.dart`.
- **The API's many `/debug-target-*` routes** (`debug-target-html`, `-scripts`, `-network`, `-responses`, `-price-keys`, etc.) are scratch/diagnostic endpoints from reverse-engineering Target's site. They are not part of the product flow — `/product`, `/search-deals`, and `/send-price-drop-push` are the real endpoints.
- **Target scraping relies on hardcoded values** — the RedSky `key` and `store_id=1771` in `scrapeTarget()`. Target support is effectively a fallback (`/debug` reports `targetEnabled: false`); Nike is the primary supported retailer.
- **No automated tests of substance** — `test/widget_test.dart` is the default Flutter counter test and does not match this app.
