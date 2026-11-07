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
- **Net worth at a glance** — the home screen shows total assets, total liabilities and your net worth, converted into a single base currency. Assets and liabilities are grouped into **collapsible cards per category** (tap to expand for individual items; the collapsed card shows the category total).
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
- **Adaptive Material 3 UI** — light/dark/system themes, **Material You** dynamic color on Android 12+, a bottom navigation bar on phones and a navigation rail on tablets and larger windows.
- **Localized UI** — English plus Spanish, Brazilian Portuguese, French, German, Japanese, Korean, Simplified Chinese, Italian, Hindi, Arabic, Indonesian, Turkish, Polish, Dutch, Vietnamese, Thai, Russian, Swedish, Danish and Norwegian Bokmål. By default, Okanzo uses the first supported language in the device's preferred-language list and falls back to English if none is supported. Choose **Settings → App language** to override it; the choice takes effect immediately and persists across restarts. Select **Use device language** to return to automatic selection. Arabic uses right-to-left layout. Exchange selection and preference dialogs are localized too. Changing app language does not change your base currency or device-based number formatting.

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

The test suite covers the pieces where behaviour must be exact: currency formatting and rounding, net-worth and FX conversion, asset/liability form validation and entity mapping, category ordering, list labels, localization coverage, quote/FX response parsing, and — most importantly — the encrypted backup format, which is verified byte-for-byte against a file produced by the original Android implementation.

### Migrating from the Android (Kotlin) release

The Flutter app uses the same `MWB1` encrypted backup container as the earlier Android release, so backups exported from the old app import directly here. The on-disk database itself is *not* migrated in place: the SQLCipher passphrase is now stored through `flutter_secure_storage`, so an existing older database cannot be opened. **Export an encrypted backup from the old app and import it after installing this one.**

## License

Released under the [MIT License](LICENSE). Okanzo is an independent, open-source project and is not affiliated with or endorsed by Google or Apple. It uses Google's Material Design system for its UI.
