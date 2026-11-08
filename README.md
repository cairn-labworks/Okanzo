# Okanzo

A private, offline-first app for tracking your **net worth** — your assets minus your liabilities — organised into portfolios. Built with Flutter and Material 3, for **Android and iOS**.

> Your financial data is stored **encrypted on your device** and never leaves it, except when you deliberately export an encrypted backup.

## Features

- **Assets** — track stocks, mutual funds/ETFs, crypto, gold, cash, bank deposits, real estate, vehicles, bonds and more. Each asset type shows only the fields that make sense for it.
  - **Stocks / funds / crypto**: enter a ticker symbol, quantity and currency, and Okanzo fetches the latest closing price to compute the holding's value automatically.
    - For **crypto**, bare symbols such as `BTC` and `ETH` use Yahoo Finance's USD pairs (`BTC-USD`, `ETH-USD`). Explicit pairs such as `BTC-EUR` are preserved. Existing crypto holdings with bare symbols use the same lookup when you refresh prices.
    - Fetched prices are converted from the quote's currency into the holding's selected currency using cached exchange rates, including when refreshing saved holdings. Changing a market holding's currency converts its cached price instead of only changing the currency symbol. Fetching or refreshing never resets the selected currency. Missing rates are fetched as needed; if conversion fails or the quote omits its currency, the previous price and currency are kept and an error is reported. Portfolio totals are then converted to your base currency. Changing the asset type or ticker clears the previous quote until you fetch or refresh again.
  - **International exchanges**: choose an exchange for stocks and funds, then enter the local ticker. Okanzo adds Yahoo Finance's suffix automatically. Selecting an exchange supplies a default currency, which you can change. The selector includes NYSE/Nasdaq, Shanghai, Japan Exchange Group (Tokyo), Hong Kong, BSE (India), and Euronext Paris, Amsterdam, Brussels, Lisbon, Dublin, Oslo and Milan. For example, choose Hong Kong and enter `0700`, or BSE and enter `RELIANCE`. Full tickers such as `0700.HK` and `RELIANCE.BO` also work. Choose **Other / full Yahoo ticker** for additional markets such as Shenzhen (`000001.SZ`), London (`VOD.L`), India's NSE (`RELIANCE.NS`) or Toronto (`SHOP.TO`). Quotes in minor units, such as British pence, are converted to their standard currency units before valuation. Existing holdings keep their exchange-qualified tickers; no database or backup migration is needed. Quote availability and delays depend on [Yahoo Finance's exchange coverage](https://help.yahoo.com/kb/finance/complete-list-markets-exchanges-yahoo-finance-sln2310.html).
    - **Preferred exchanges**: the dropdown shows only your saved shortlist, starting with **US (NYSE / Nasdaq)**. Its final **Select preferred exchanges...** option opens a checkbox popup where you can select or deselect exchanges. Preferences apply to stocks and funds across portfolios and persist across app restarts. Selecting none is allowed: the dropdown then shows only the preference-management option, and full Yahoo tickers can still be entered. Existing holdings retain their exchange and quote even when it is removed from the shortlist.
  - **Gold** and other quantity-based assets: enter a quantity and a price per unit.
  - **Cash, property, vehicles, …**: enter a single value.
- **Liabilities** — track loans, mortgages, credit cards, pending payments and taxes.
- **Focused entry forms** — a large page heading leads into the value or live estimate, followed by compact type/currency/exchange chips and understated underlined fields. Related valuation fields sit side by side when space and text size allow; narrow or large-text layouts stack them. Long-press the exchange chip for ticker/suffix guidance. Optional notes expand in place and existing notes open automatically. The save action follows the form rather than sitting in a fixed bottom bar; single-value assets avoid repeating the value. Currency rounding and all valuation modes remain unchanged.
- **Grouped settings** — open **Appearance**, **Currency**, **Security**, **Data** or **About** from the compact, descriptive category list. Back returns to the category list, then to the app. All existing preferences and actions remain available.
- **Quiet overview** — the home screen has an unboxed net-worth headline, simple asset/liability totals and compact tabs always labelled **Assets** and **Liabilities**, without counts. The selected section uses one quiet panel with **collapsible category rows** (tap to expand individual holdings; collapsed rows show category totals and item counts). Expansion and ordering remain available, and adding a record selects its corresponding section. Everything is converted into your base currency.
  - **Simple net worth**: enable **Settings → Currency → Simple net worth** to shorten only the home headline. Thousands are abbreviated from 1,000 (e.g. `$7K` for `$7,054`); smaller amounts stay exact. INR uses lakh/crore for larger values (e.g. `₹1.65 Cr` for `₹1,65,34,234`); other currencies use M/B (e.g. `$165.3M`). The option is off by default and persists across restarts. Detailed totals stay exact, and **Hide balances** still masks the headline.
- **Custom ordering** — long-press and drag to reorder category cards, or reorder items within a category (items stay within their own type). Your order is saved.
- **Portfolios** — create multiple portfolios (e.g. *Personal*, *Family*, *Business*), set a **default** that powers the home screen, and switch between them at any time. Each portfolio has its own net worth.
- **Statistics** — donut charts breaking down assets and liabilities by category, with per-slice percentages and totals in your base currency.
- **Multi-currency** — hold assets in any currency; Okanzo converts everything into your chosen base currency using cached exchange rates.
- **Security & privacy**
  - The local database is encrypted with **SQLCipher (AES-256)**; the key is generated on-device and stored in the **Android Keystore** / **iOS Keychain**.
  - Optional **app lock** with biometrics or device PIN, re-locking whenever the app leaves the foreground.
  - Screenshot protection: `FLAG_SECURE` on Android, and a blur overlay in the iOS app switcher.
  - **Hide balances** hides every monetary amount behind `••••` with one tap.
- **Encrypted export / import** — back up selected portfolios (or all of them) to a password-protected file (AES-256-GCM with PBKDF2-HMAC-SHA256), and restore them on any device.
- **Unified precision UI** — deep-green surfaces, sage accents, crisp number typography, quiet inset cards and subtle separators across the dashboard, statistics, portfolios, settings, entry forms and dialogs. **Settings → Appearance → Theme** is the single appearance control: **Light** uses the light palette, **Dark** uses **Midnight**, and **System default** switches between those variants with the device. Material You wallpaper colors remain available in light mode on Android 12+; dark mode keeps the fixed Midnight palette. Existing light/dark/system choices and legacy Midnight preferences are preserved. Navigation adapts from a bottom bar on phones to a rail on tablets and larger windows.
- **Localized UI** — English plus Spanish, Brazilian Portuguese, French, German, Japanese, Korean, Simplified Chinese, Italian, Hindi, Arabic, Indonesian, Turkish, Polish, Dutch, Vietnamese, Thai, Russian, Swedish, Danish and Norwegian Bokmål. By default, Okanzo uses the first supported language in the device's preferred-language list and falls back to English if none is supported. Choose **Settings → Appearance → App language** to override it; the choice takes effect immediately and persists across restarts. Select **Use device language** to return to automatic selection. Arabic uses right-to-left layout. Exchange selection and preference dialogs are localized too. Changing app language does not change your base currency or device-based number formatting.
- **What's new highlights** — a pop-up summarizes the key highlights of the latest release the first time you open Okanzo after installing or updating to a new version (after unlocking if app lock is enabled). You can also reopen the release highlights anytime from **Settings → About → What's new**.
- **App information** — **Settings → About → Okanzo** shows the installed version, open-source licence information and dependency licences. It is separate from **What's new** and does not mark release highlights as read.

## Privacy

Okanzo is **offline-first**. The only network calls it makes are:

1. **Stock/fund/crypto prices** — sends only the ticker symbol to a public finance endpoint.
2. **Exchange rates** — sends only a base currency code to a public, key-less rates endpoint.

No account, no analytics, no tracking. Your portfolio values, names and holdings are never transmitted. Read the full [privacy policy](https://cairn-labworks.github.io/Okanzo/privacy/).

## Tech stack

| Area | Choice |
| --- | --- |
| Language | Dart |
| UI | Flutter, Material 3 |
| Architecture | MVVM (`ChangeNotifier` view models) with a lightweight manual DI container |
| Persistence | `sqflite_sqlcipher` (encrypted SQLite) |
| Keys & secrets | `flutter_secure_storage` (Android Keystore / iOS Keychain) |
| Auth | `local_auth` (biometrics / device credential) |
| Preferences | `shared_preferences` |
| Networking | `http` with hand-written JSON models |
| Crypto | `pointycastle` (PBKDF2-HMAC-SHA256 + AES-256-GCM) |
| Dynamic color | `dynamic_color` + `material_color_utilities` |

### Project layout

```
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

## Building

Requirements:

- Flutter (stable channel, Dart SDK ≥ 3.13)
- Android: JDK 17 and the Android SDK (minSdk 26 / Android 8.0+)
- iOS: Xcode 15+ and CocoaPods (iOS 15+)

```bash
flutter pub get
flutter run                 # debug on a connected device
flutter build appbundle     # Android, Google Play bundle (.aab)
flutter build apk --split-per-abi   # Android, per-ABI APKs
flutter build ipa           # iOS
```

The application id / bundle id is `com.cairnlabworks.okanzo`; the current version is defined in `pubspec.yaml`.

### Release signing

Release builds are signed with the Cairn Labworks upload key, which is never committed. Create
`android/key.properties` (git-ignored):

```properties
storeFile=C:/path/to/okanzo-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

`storeFile` is resolved relative to `android/app/`, or can be an absolute path. Without
`key.properties`, release builds fall back to the debug key so `flutter run --release` still works,
but Google Play rejects those builds. On Google Play, use Play App Signing: Google holds the app
signing key and this key is only the upload key.

The **Release** workflow (`.github/workflows/release.yml`) runs on `v*` tags, or manually from the
Actions tab. It builds the signed `.aab` and per-ABI APKs and attaches them as a workflow artifact. It
needs these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The upload keystore, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias, for example `upload` |
| `ANDROID_KEY_PASSWORD` | Key password |

### Creating a release

Invoke `/create-release` in Copilot, or ask to release the latest `main` and publish
to F-Droid. The [release skill](.github/skills/create-release/SKILL.md) includes all
merged changes since the previous release, validates signed artifacts, and publishes
the GitHub release using F-Droid's expected APK filenames. It preserves uncommitted
work and uses your authorized GitLab account if the F-Droid build recipe needs an
update. Official F-Droid availability depends on its source build, reproducibility
verification, and index publication; Google Play is not part of this workflow.

## Quality checks

```bash
dart format .
flutter analyze
flutter test
```

Localization tests cover all 21 locales, message placeholders, device-language
changes, persisted app-language overrides, English fallback, Arabic layout,
localized date labels and exchange preferences. On a device, also check text
wrapping with a larger font size and
the native app-lock and backup-file dialogs in your preferred language. On iOS,
the supported languages are declared in `ios/Runner/Info.plist` so they are
available to the system's app-language selection.

For the live Android exchange smoke test, use a dedicated emulator:

```bash
flutter test integration_test/exchange_support_test.dart -d <android-device-id>
```

This test creates a separate test portfolio and exercises the real Yahoo API,
exchange selector, encrypted database, saving/reopening holdings and price
refresh. It requires network access and depends on Yahoo quote availability.

To run only the live currency regression on a dedicated emulator:

```sh
flutter test integration_test/exchange_support_test.dart -d <android-device-id> --plain-name "market currency conversion survives saving, refresh and relaunch"
```

This checks USD-to-EUR-to-GBP conversion for crypto, stocks and funds through the currency picker, encrypted storage, repeated quote fetches, portfolio refresh, base-currency totals and database reopening.

To test simple net worth on an Android device (including wireless debugging):

```bash
flutter build apk --debug --build-number <installed-debug-version-code-or-higher> \
  --target integration_test/simple_net_worth_test.dart
flutter drive --driver test_driver/simple_net_worth.dart \
  --target integration_test/simple_net_worth_test.dart \
  --use-application-binary build/app/outputs/flutter-apk/app-debug.apk \
  --no-pub -d <android-device-id>
```

This uses the separate debug app, creates temporary INR/USD portfolios, and
checks the settings toggle, detailed totals, balance masking and persistence
after relaunch. A 14-value matrix covers zero, fractions, small amounts, thousand
boundaries, negatives, millions, billions and INR lakh/crore. Each matrix headline
must match its expected text, fit on one line, and use at most eight characters;
abbreviated amounts must also be shorter than the detailed format.
It restores the original preferences and removes only portfolios created by the
current test run when finished. Use `flutter drive` rather than `flutter test`
to avoid uninstalling the debug app after testing. Check the installed debug
version code first:

```bash
adb -s <android-device-id> shell dumpsys package com.cairnlabworks.okanzo.debug
```

Set `--build-number` on the APK build to at least that version code to avoid a
downgrade-triggered uninstall; `flutter drive` consumes the prebuilt APK. Keep
the host driver inside this repository so its package imports resolve.
If app lock is enabled, unlock the debug app when prompted.
Keep the device awake and unlocked, with the debug app in the foreground,
throughout testing. A sleeping device can stop Flutter frame pumping and stall
both the test and its settings cleanup.

For the selected Midnight layout and its device regressions:

```bash
flutter build apk --debug --build-number <installed-debug-version-code-or-higher> \
  --target integration_test/midnight_precision_test.dart
flutter drive --driver test_driver/simple_net_worth.dart \
  --target integration_test/midnight_precision_test.dart \
  --use-application-binary build/app/outputs/flutter-apk/app-debug.apk \
  --no-pub -d <android-device-id>
```

This checks the descriptive settings drill-in, heading placement, compact chips,
paired valuation fields, inline save actions, encrypted persistence and 150%
Arabic RTL on the actual device. It intentionally keeps **Midnight** selected,
restores all other preferences and removes only its own test portfolio. After
testing, rebuild and reinstall the normal debug entrypoint (`lib/main.dart`)
with the same adequate build number so launching the app does not rerun tests.

The test suite covers the pieces where behaviour must be exact: currency formatting and rounding, net-worth and FX conversion, asset/liability form validation and entity mapping, category ordering, list labels, localization coverage, quote/FX response parsing, and — most importantly — the encrypted backup format, which is verified byte-for-byte against a file produced by the original Android implementation.

### Migrating from the Android (Kotlin) release

The Flutter app uses the same `MWB1` encrypted backup container as the earlier Android release, so backups exported from the old app import directly here. The on-disk database itself is *not* migrated in place: the SQLCipher passphrase is now stored through `flutter_secure_storage`, so an existing older database cannot be opened. **Export an encrypted backup from the old app and import it after installing this one.**

## License

Released under the [MIT License](LICENSE). Okanzo is an independent, open-source project and is not affiliated with or endorsed by Google or Apple. It uses Google's Material Design system for its UI.
