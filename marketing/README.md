# Okanzo — marketing screenshots

Store / landing-page promo screenshots in a **dark & colorful** style
(inspired by the framing of [Streak](https://github.com/InlitX/streak)).
Each poster is a 1080×1920 composite (rendered at 2× → 2160×3840) with a badge,
headline, subtitle, a device mockup of the app, floating feature callouts and a
bottom brand/feature strip.

| File | Screen | Headline |
|------|--------|----------|
| `screenshots/01-networth.png`   | Home            | Your wealth. One glance. |
| `screenshots/02-statistics.png` | Statistics      | Numbers, not guesswork. |
| `screenshots/03-currency.png`   | Home (expanded) | Every currency. One total. |
| `screenshots/04-private.png`    | Lock screen     | Private by design. |
| `screenshots/05-portfolios.png` | Portfolios      | Many portfolios. One you. |
| `screenshots/06-backup.png`     | Export          | Your data. Your keys. |

## Regenerating

The posters are generated from a single self-contained HTML file and rendered
with headless Chrome/Edge (no build step or network needed).

```powershell
# generator: marketing/generate.html  (append ?p=<0-5> to render one poster)
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$src    = "marketing\generate.html"
0..5 | ForEach-Object {
  & $chrome --headless=new --disable-gpu --hide-scrollbars `
    --force-device-scale-factor=2 --window-size=1080,1920 `
    --screenshot="screenshots\poster-$_.png" "file:///$($src -replace '\\','/')?p=$_"
}
```

Edit headlines, captions, callouts and the app-screen mockups in the `POSTERS`
and screen-builder functions inside the generator, then re-run.

## Exchange feature screenshots

Unlike the promotional posters above, these are actual Android emulator
captures of the app, using a **Global demo** portfolio with sample holdings:

| File | Screen |
|------|--------|
| [exchange-picker.png](screenshots/exchanges/exchange-picker.png) | Shortlist dropdown with a final preference-management action |
| [preferred-exchanges.png](screenshots/exchanges/preferred-exchanges.png) | Checkbox popup for choosing preferred exchanges |
| [empty-exchanges.png](screenshots/exchanges/empty-exchanges.png) | Dropdown with no preferred exchanges selected |
| [bse-quote.png](screenshots/exchanges/bse-quote.png) | BSE holding with a fetched INR quote |
| [global-portfolio.png](screenshots/exchanges/global-portfolio.png) | International holdings in one portfolio |

To regenerate them on a dedicated Android emulator:

```bash
flutter drive \
  --driver=test_driver/exchange_screenshots.dart \
  --target=integration_test/exchange_support_test.dart \
  --dart-define=CAPTURE_SCREENSHOTS=true \
  -d <android-device-id>
```

The capture uses Flutter's integration-test image surface; the app's
`FLAG_SECURE` screenshot protection stays enabled. The full live exchange smoke
test also runs, so network access and Yahoo quote availability are required.
