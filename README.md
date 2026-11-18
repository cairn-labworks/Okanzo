<div align="center">

<img src="marketing/banner.png" alt="Okanzo — A private, offline-first net worth tracker." width="100%" />

</div>

---

<div align="center">

### Okanzo

<img src="marketing/icon.svg" width="72" alt="Okanzo logo" />

### A private, offline-first net worth tracker

Track your assets and liabilities across currencies and portfolios — encrypted on your device, with no accounts and no cloud.

<br/>

<p>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white" />
  <img alt="Dart" src="https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white" />
  <img alt="Android" src="https://img.shields.io/badge/Android-3DDC84?style=flat&logo=android&logoColor=white" />
  <img alt="License MIT" src="https://img.shields.io/badge/License-MIT-3D6249?style=flat" />
  <img alt="AES-256 · No tracking" src="https://img.shields.io/badge/AES--256%20%C2%B7%20No%20tracking-204938?style=flat&logo=shield&logoColor=white" />
  <img alt="Downloads" src="https://img.shields.io/github/downloads/cairn-labworks/Okanzo/total?style=flat&logo=github&logoColor=white&label=Downloads&color=3D6249" />
</p>

<br/>

<a href="https://f-droid.org/packages/com.cairnlabworks.okanzo/"><img alt="Get it on F-Droid" src="marketing/badges/get-it-on-fdroid.svg" height="60" /></a>
&nbsp;
<a href="https://github.com/cairn-labworks/Okanzo/releases"><img alt="Get it on GitHub" src="marketing/badges/get-it-on-github.svg" height="60" /></a>

<br/>

<sub>
  <a href="#features">Features</a> ·
  <a href="#coming-from-an-earlier-release">Migration</a> ·
  <a href="#download">Download</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#translations">Translations</a> ·
  <a href="#building">Building</a> ·
  <a href="#quality-checks">Quality checks</a>
</sub>

</div>

---

<div align="center">

<img src="marketing/screenshots/01-networth.png" alt="Quiet overview" width="240" />
<img src="marketing/screenshots/02-statistics.png" alt="Statistics" width="240" />
<img src="marketing/screenshots/03-currency.png" alt="Multi-currency" width="240" />

<img src="marketing/screenshots/04-private.png" alt="Private by design" width="240" />
<img src="marketing/screenshots/05-portfolios.png" alt="Portfolios" width="240" />
<img src="marketing/screenshots/06-backup.png" alt="Encrypted backup" width="240" />

<sub><b>Quiet overview</b> · <b>Statistics</b> · <b>Multi-currency</b> · <b>Private by design</b> · <b>Portfolios</b> · <b>Encrypted backup</b></sub>

</div>

---

## Overview

Okanzo is an open source, offline-first app for tracking your **net worth** — your assets minus your liabilities — organised into portfolios, built with Flutter and Material 3 for **Android**.

Your financial data is stored **encrypted on your device** and never leaves it, except when you deliberately export an encrypted backup. No accounts, no analytics, no ads.

---

## Features

<table>
<tr>
<td width="50%" valign="top">

### Quiet overview & portfolios

- Unboxed net-worth headline, clean asset and liability totals, and compact **Assets** and **Liabilities** tabs
- A single quiet panel with **collapsible category rows** showing category totals and item counts until expanded
- **Simple net worth** (`Settings → Currency → Simple net worth`) shortens only the home headline from 1,000 upward (`$7K`, `$165.3M`, or `₹1.65 Cr` in INR lakh/crore) while keeping detailed totals exact
- **Multiple portfolios** (*Personal*, *Family*, *Business*), a **Default** that powers the home screen, and instant switching
- **Custom ordering**: long-press and drag to reorder categories or items within their category

</td>
<td width="50%" valign="top">

### Global markets & multi-currency

- Track **stocks, mutual funds/ETFs, crypto, gold, cash, bank deposits, real estate, vehicles, bonds**, plus **loans, mortgages, credit cards, pending payments and taxes**
- **International exchanges**: NYSE/Nasdaq, Shanghai, Tokyo, Hong Kong, BSE (India), and Euronext Paris, Amsterdam, Brussels, Lisbon, Dublin, Oslo and Milan — or **Other / full Yahoo ticker** (`000001.SZ`, `VOD.L`, `RELIANCE.NS`, `SHOP.TO`). Quotes in minor units (such as British pence) convert automatically; [Yahoo Finance coverage](https://help.yahoo.com/kb/finance/complete-list-markets-exchanges-yahoo-finance-sln2310.html) applies
- **Preferred exchanges** shortlist starting with **US (NYSE / Nasdaq)**, customisable via **Select preferred exchanges...** (including an empty shortlist) while preserving existing holdings
- **Company, coin or ticker search**: type at least two characters in the stock, fund or crypto search field for Yahoo Finance suggestions showing the name and ticker, plus the exchange for stocks/funds. Crypto suggestions show full trading pairs such as `BTC-USD`; explicit non-USD pairs are preserved. Select a listing to fill its symbol and, if blank, its name. Manual ticker entry still works offline or when search is unavailable
- **Smart crypto & FX conversion**: bare crypto tickers (`BTC` → `BTC-USD`, explicit `BTC-EUR` preserved), quote-to-holding currency conversion without resetting your chosen currency, and automatic portfolio conversion into your base currency

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Focused forms & statistics

- **Focused entry forms**: a large page heading leads into the value or live estimate, compact type/currency/exchange chips (long-press the exchange chip for suffix guidance), paired underlined valuation fields, expandable optional notes and an inline save button
- **Statistics**: interactive donut charts breaking down overview (assets vs. liabilities), assets by category and liabilities by category in your base currency
- **What's new** highlights after installing or updating (`Settings → About → What's new`), separate from **Settings → About → Okanzo** app & licence details

</td>
<td width="50%" valign="top">

### Midnight, sage & 21 languages

- **Unified precision UI**: deep-green surfaces, sage accents, tabular number typography, quiet inset cards and subtle separators across every screen
- Single **Settings → Appearance → Theme** control: **Light** uses the sage palette (with optional **Material You** wallpaper colors on Android 12+), **Dark** uses **Midnight**, and **System default** follows the device
- **Grouped settings** (**Appearance**, **Currency**, **Security**, **Data**, **About**) and adaptive navigation (bottom bar on phones, navigation rail on tablets and wide windows)
- **21 languages** with immediate override or automatic device-language selection, including right-to-left Arabic layout

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Security & privacy

- Local database encrypted at rest with **SQLCipher (AES-256)**, keyed through **Android Keystore**
- Optional **app lock** with fingerprint, biometrics or device PIN, re-locking whenever Okanzo leaves the foreground
- **Screenshot protection**: `FLAG_SECURE` on Android prevents screen captures and recent-apps previews by default, with a toggle under **Settings → Security → Block screenshots**
- **Hide balances** masks every monetary figure behind `••••` in one tap

</td>
<td width="50%" valign="top">

### Encrypted backups

- Export selected portfolios — or all of them — into a single password-protected `.okanzo` file (**AES-256-GCM** with **PBKDF2-HMAC-SHA256**)
- Restore backups on any device with zero cloud dependency
- Byte-for-byte compatible with the `MWB1` encrypted backup format from the earlier Android release

</td>
</tr>
</table>

---

## Coming from an earlier release?

<details>
<summary><b>Migrating from the Android (Kotlin) release</b></summary>

The Flutter app uses the same `MWB1` encrypted backup container as the earlier Android release, so backups exported from the old app import directly here. The on-disk database itself is *not* migrated in place: the SQLCipher passphrase is now stored through `flutter_secure_storage`, so an existing older database cannot be opened.

**Export an encrypted backup from the old app and import it after installing this one.**

<div align="center"><sub><b>Settings → Data → Import portfolios</b></sub></div>

</details>

---

## Download

[**F-Droid**](https://f-droid.org/packages/com.cairnlabworks.okanzo/) is the easiest way on Android: F-Droid independently verifies Okanzo's reproducible builds against the developer-signed releases and keeps the app updated automatically.

| Platform | Status |
|----------|--------|
| Android (8.0 / API 26+) | ✅ Supported ([F-Droid](https://f-droid.org/packages/com.cairnlabworks.okanzo/) & [GitHub Releases](https://github.com/cairn-labworks/Okanzo/releases)) |

<details>
<summary><b>Install the APK yourself</b></summary>

Prefer direct downloads? Signed per-ABI APKs and `SHA256SUMS` are attached to every release on the [**Releases**](https://github.com/cairn-labworks/Okanzo/releases) page:

| APK | Architecture | For |
|-----|--------------|-----|
| `com.cairnlabworks.okanzo_<base>2.apk` | `arm64-v8a` | Modern 64-bit phones — **pick this one** |
| `com.cairnlabworks.okanzo_<base>1.apk` | `armeabi-v7a` | Older 32-bit Android devices |
| `com.cairnlabworks.okanzo_<base>3.apk` | `x86_64` | Emulators and x86_64 tablets |

Runs on **Android 8.0 (Oreo) and newer**.

</details>

---

## Privacy

> [!IMPORTANT]
> Okanzo is **offline-first**, with no accounts, no analytics, no ads and no tracking. Your portfolio values, names and holdings never leave your device unless you export an encrypted backup yourself.
>
> Network access is used **only** for keyless public lookups:
> 1. **Stock, fund & crypto prices** — sends only the ticker symbol to a public finance endpoint when you fetch, save (if not yet priced) or refresh market-linked holdings.
> 2. **Exchange rates** — sends only a base currency code to a public rates endpoint (at most every 12 hours, or when refreshed manually).
> 3. **Company/coin/ticker search** — sends only text typed into the stock, fund or crypto search field to Yahoo Finance after a short pause (at least two characters). Asset names, quantities and portfolio data are not included.

Search uses Yahoo Finance's free, keyless public search endpoint, the same provider as price lookups. This is an **unofficial API**, with no availability guarantee or service-level agreement; rate limits and coverage may change. No account, API key, paid plan or additional dependency is required. Search results are global rather than restricted to preferred exchanges; choosing a stock/fund listing sets its exchange, while crypto selection retains the exact trading pair. Both preserve your holding currency and any custom asset name.

Read the full [**privacy policy**](https://cairn-labworks.github.io/Okanzo/privacy/).

---

## Translations

Okanzo ships with **21 built-in app languages** — English, Spanish, Brazilian Portuguese, French, German, Japanese, Korean, Simplified Chinese, Italian, Hindi, Arabic (RTL), Indonesian, Turkish, Polish, Dutch, Vietnamese, Thai, Russian, Swedish, Danish and Norwegian Bokmål.

By default, Okanzo selects the first supported language in your device's preferred-language list and falls back to English. Override it anytime in **Settings → Appearance → App language** (or choose **Use device language** to return to automatic selection) without changing your base currency or regional number formatting.

---

## Architecture & tech stack

| Area | Choice |
| --- | --- |
| Language | Dart |
| UI | Flutter, Material 3 |
| Architecture | MVVM (`ChangeNotifier` view models) with a lightweight manual DI container |
| Persistence | `sqflite_sqlcipher` (encrypted SQLite) |
| Keys & secrets | `flutter_secure_storage` (Android Keystore) |
| Auth | `local_auth` (biometrics / device credential) |
| Preferences | `shared_preferences` |
| Networking | `http` with hand-written JSON models |
| Crypto | `pointycastle` (PBKDF2-HMAC-SHA256 + AES-256-GCM) |
| Dynamic color | `dynamic_color` + `material_color_utilities` |

<details>
<summary><b>Project layout</b></summary>

```text
lib/
├── data/
│   ├── local/        Database, entities, DAOs (encrypted SQLCipher)
│   ├── remote/       Stock price + FX rate APIs
│   ├── repository/   Repositories + net-worth calculation
│   ├── security/     Database key provider + backup crypto
│   └── backup/       Encrypted export / import
├── domain/model/     Enums and value types
├── di/               AppContainer + AppScope
├── ui/
│   ├── theme/        Material 3 theme, color, dynamic color
│   ├── home/         Net worth home screen
│   ├── asset/        Asset editor
│   ├── liability/    Liability editor
│   ├── portfolio/    Portfolio management
│   ├── statistics/   Breakdown charts
│   ├── settings/     Settings, export/import, app lock
│   ├── lock/         Biometric lock screen
│   ├── navigation/   Adaptive shell (navigation bar / rail)
│   └── components/   Reusable widgets
└── util/             Currency, ordering, biometric and time helpers
```

Business logic lives in plain Dart (no Flutter imports) so it can be unit-tested with `dart test`.

</details>

---

## Building

Requirements:

- Flutter (stable channel, Dart SDK ≥ 3.13)
- Android: JDK 17 and the Android SDK (minSdk 26 / Android 8.0+)

```bash
flutter pub get
flutter run                         # debug on a connected device
flutter build appbundle             # Android, Google Play bundle (.aab)
flutter build apk --split-per-abi   # Android, per-ABI APKs
```

The application ID is `com.cairnlabworks.okanzo`; the current version is defined in `pubspec.yaml`.

<details>
<summary><b>Release signing &amp; publishing (<code>/create-release</code>)</b></summary>

Release builds are signed with the Cairn Labworks upload key, which is never committed. Create `android/key.properties` (git-ignored):

```properties
storeFile=C:/path/to/okanzo-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

`storeFile` is resolved relative to `android/app/`, or can be an absolute path. Without `key.properties`, release builds fall back to the debug key so `flutter run --release` still works locally, but Google Play rejects those builds. On Google Play, use Play App Signing: Google holds the app signing key and this key is only the upload key.

The **Release** workflow (`.github/workflows/release.yml`) runs on `v*` tags, or manually from the Actions tab. It builds the signed `.aab` and per-ABI APKs inside F-Droid's pinned Linux build image with canonical checkout/SDK locations and individual ABI targets, scans every signed APK with `fdroid scanner --exit-code`, verifies the bundle omits opaque dependency metadata, and uploads the signed artifacts. Android builds keep `dependenciesInfo.includeInApk` and `includeInBundle` disabled, as required by F-Droid. Official reproducibility still requires F-Droid's independent verification.

Required repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The upload keystore, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias, for example `upload` |
| `ANDROID_KEY_PASSWORD` | Key password |

Invoke `/create-release` in Copilot, or ask to release the latest `main` and publish to F-Droid. The [release skill](.github/skills/create-release/SKILL.md) includes all merged changes since the previous release, validates signed artifacts, and publishes the GitHub release using F-Droid's expected APK filenames. Official F-Droid availability depends on its source build, reproducibility verification and index publication; Google Play is outside that workflow.

GitLab operations use the GitLab CLI (`glab`) rather than a browser session.
Install it with your package manager and authenticate once using OAuth:

```sh
glab auth login --hostname gitlab.com --device \
  --git-protocol https --api-protocol https \
  --setup-git-credential-helper
glab auth status --hostname gitlab.com
```

Authorize the device code directly in GitLab. Confirm that credentials are stored
in the OS keyring, not plaintext configuration; future sessions reuse that login.
Use explicit GitLab project URLs for `glab --repo` commands from this GitHub
checkout, and the pipeline's actual project ID when inspecting fork CI jobs.

</details>

---

## Quality checks

```bash
dart format .
flutter analyze
flutter test
```

The test suite covers currency formatting and rounding, net-worth and FX conversion, asset/liability form validation and entity mapping, category ordering, list labels, 21-locale localization coverage, quote/FX response parsing, and byte-for-byte verification of the `MWB1` encrypted backup format.

<details>
<summary><b>Android emulator &amp; physical-device integration tests</b></summary>

For the live Android exchange smoke test on a dedicated emulator (requires network access and Yahoo quote availability):

```bash
flutter test integration_test/exchange_support_test.dart -d <android-device-id>
```

To run only the live currency regression on a dedicated emulator:

```sh
flutter test integration_test/exchange_support_test.dart -d <android-device-id> --plain-name "market currency conversion survives saving, refresh and relaunch"
```

To test simple net worth or Midnight layout regressions on an Android device without uninstalling the debug app afterward, check the installed debug version code first:

```bash
adb -s <android-device-id> shell dumpsys package com.cairnlabworks.okanzo.debug
```

Set `--build-number` on the APK build to at least that version code to avoid a downgrade-triggered uninstall, and keep the device awake and unlocked with the debug app in the foreground throughout testing. The APK must also use the **same signing key** as the installed debug app. First run `adb install -r` as shown below: if it reports a signing mismatch, **stop** rather than uninstalling the app. Flutter's installer can automatically uninstall on failure, deleting app data. Always pass `--keep-app-running` to `flutter drive`; without it, drive uninstalls the app after testing:

```bash
flutter build apk --debug --build-number <installed-debug-version-code-or-higher> \
  --target integration_test/simple_net_worth_test.dart
adb -s <android-device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
flutter drive --driver test_driver/simple_net_worth.dart \
  --target integration_test/simple_net_worth_test.dart \
  --use-application-binary build/app/outputs/flutter-apk/app-debug.apk \
  --keep-app-running --no-pub -d <android-device-id>
```

For the Midnight layout, settings drill-in, paired valuation fields and 150% Arabic RTL device regressions:

```bash
flutter build apk --debug --build-number <installed-debug-version-code-or-higher> \
  --target integration_test/midnight_precision_test.dart
adb -s <android-device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
flutter drive --driver test_driver/simple_net_worth.dart \
  --target integration_test/midnight_precision_test.dart \
  --use-application-binary build/app/outputs/flutter-apk/app-debug.apk \
  --keep-app-running --no-pub -d <android-device-id>
```

After device testing, rebuild and reinstall the normal debug entrypoint (`lib/main.dart`) with the same adequate build number so launching the app does not rerun tests.

For live company/coin/ticker typeahead, international listing selection, fund and crypto search,
price fetching and saving on a physical device, use the same build-and-drive
commands with `--target integration_test/stock_search_test.dart`. This test uses
a temporary portfolio and removes it afterward without changing existing holdings,
the default portfolio or preferences. It also supports an empty debug installation.
The phone must have internet access.

</details>

---

## Support & license

<div align="center">

Okanzo is free, open source and free of ads or tracking — and stays that way.

If Okanzo is useful to you, starring the repository or reporting issues on [**GitHub Issues**](https://github.com/cairn-labworks/Okanzo/issues) helps others discover and improve it.

<br/>

<a href="https://www.star-history.com/#cairn-labworks/Okanzo&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=cairn-labworks/Okanzo&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=cairn-labworks/Okanzo&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=cairn-labworks/Okanzo&type=Date" width="600" />
  </picture>
</a>

<br/>
<br/>

Released under the <a href="LICENSE"><b>MIT License</b></a>. Okanzo is an independent, open-source project and is not affiliated with or endorsed by Google. It uses Google's Material Design system for its UI.

</div>
