# Brand

`brand.json` holds the product name, the repository and the website. Everything a user sees reads them from there.

## Renaming

1. Change `name` in `brand.json`, and `repository` or `website` if those move too.
2. Run `python3 scripts/apply_brand.py`. It regenerates the constants, writes the values into the platform files that cannot read JSON themselves and swaps the old name for the new one in `README.md`, `NOTICE`, `COMMERCIAL-LICENSE.md`, `CONTRIBUTING.md` and `licensing/*.md`.
3. Read the diff of the license texts before you publish.
4. Rebuild what ships: the apps, the PWA copy in `landing-page/public/pwa`, the landing page into `site/`, the promo renders.
5. The desktop apps look for the project in `~/Documents/<name>`. Move the folder along and recreate `venv`.

`tests/test_brand.py` fails when a platform file no longer matches `brand.json` (`apply_brand.py --check`) and when the current name is written into code directly.

## Where the values come from

| Place | Source |
|---|---|
| Flask templates | `{{ brand_name }}` and `{{ brand_repository }}`, injected by `inject_globals` in `app/app.py` |
| Python | `brand.NAME`, `brand.REPOSITORY`, `brand.WEBSITE` from the generated `app/brand.py` |
| Web UI scripts and service worker | `BRAND_NAME`, `BRAND_REPOSITORY`, `BRAND_WEBSITE` from the generated `app/static/js/brand.js` |
| Flutter | `Brand.name`, `Brand.repository`, `Brand.website` from the generated `flutter_app/lib/brand.dart` |
| Native app shells | written by `apply_brand.py`: Android label, iOS `Info.plist`, macOS product name, scheme and test host, the trusted notification host in `AppDelegate.swift`, Windows and Linux window titles, binary names and version info, Flutter web `index.html` and `manifest.json`, Flask `manifest.json` |
| Electron | the generated `desktop/brand.json` (name, website for the update check, earlier names); `appId`, `productName`, `desktopName`, `homepage`, the Linux executable and package name, shortcut and installer names in `desktop/package.json` |
| Landing page | `{{BRAND_NAME}}`, `{{BRAND_REPOSITORY}}`, `{{BRAND_WEBSITE}}` and `{{BRAND_WEBSITE_HOST}}`, replaced at build time by `landing-page/integrations/brand-placeholder.js`; download URLs in `public/version.json` are written by `apply_brand.py` |
| Promo video | `BRAND_NAME` and `BRAND_WEBSITE` from the generated `promo-video/src/brand.ts` |
| `setup.sh`, `start.sh`, `flutter_app/android/generate_keystore.sh` | read `brand.json` with `sed` |
| macOS build script | reads `PRODUCT_NAME` from `AppInfo.xcconfig` |
| README, NOTICE, license texts | swapped by `apply_brand.py` |

## Neutral internal names

Code never carries the product name, so a rename does not touch it: classes and widgets are `App*`, web storage keys, events and CSS classes use `app-`, the landing colours are `brand-*`, the Electron app lives in `desktop/`, the frozen backend is `server`, environment variables are `HUB_*` (`HUB_DATA_DIR`, `HUB_HOST`, `HUB_PORT`, `HUB_ROOT`), the backend database is `data/hub.db`, the Flutter database is `app.db`, the Dart package is `app`. Hora Brief and lesson-heading talk to the backend through `HUB_API_TOKEN` and `hub_url`, and Hora Brief starts the app by its bundle ID.

## What still says nexus, and why

- The app ID `com.leon.nexus` (Android `applicationId` and Kotlin package, iOS and macOS bundle IDs, Linux `APPLICATION_ID`). Installed apps keep their data, keychain entries and updates only under the same ID. Changing it means a new app.
- The Android signing key (alias and certificate). A different key cannot update an installed app.
- `previousNames` in `brand.json`, the one place that knows earlier product names. On a rename, `apply_brand.py` adds the name it replaces there by itself, and `--check` fails if it is missing. Everything that picks up data from before a rename reads this list instead of spelling a name out: `app/paths.py` (`NEXUS_DATA_DIR`, `NEXUS_PORT` and the other old variables still work behind `HUB_*`; `HUB_HOST` deliberately has no fallback, so an old setting cannot put a server back on the network), `app/database.py` (`nexus.db` to `hub.db`), `flutter_app/lib/services/database_service.dart` (`nexus.db` to `app.db`), `desktop/src/profile.js` (Electron data folder, renamed only when no folder under the new name exists), `flutter_app/lib/services/legacy_import.dart` (the desktop shell asks before it copies `Documents/Nexus/data` into `Documents/<name>`, takes only the `SECRET_KEY` and `GOOGLE_*` lines from the old `.env`, word for word, asks the old install's python-dotenv what those lines meant and checks the new `.env` with it again, drops a key the backend would reject, stops with a message instead of guessing or mixing two keys, and leaves the old folder as it is) and the settings page, which also restores backups made under an earlier name.
- Other code that reads data from before the rename: `app/static/js/storage-migration.js` (browser storage keys) and `app/crypto_utils.py` (`_LEGACY_SALT_PREFIX` reads files written before the new prefix; `_STATIC_SALT` is a cryptographic parameter for files from before per-file salts and must never change).
- The website `nexus-lifehub.netlify.app`, until there is an own domain. It lives only in `brand.json`.
- Download files, `landing-page/public/install-macos.sh` and the download hints on the landing page, until builds under the new name are published.
- Git history.

## Logo

The mark is a sand circle overlapping a sage rounded square. The overlap is pine green on light backgrounds and chalk white on dark ones. The colours come from the palette of the redesign: pine is the sidebar and the day card, sand marks the current block and sage means done. The wordmark is the product name in Outfit SemiBold (600) with -2 % tracking, converted to paths. The shapes were option W in the logo drafts and the colours variant A in the colour drafts, both kept outside the repository.

| Role | Light | Dark | App icon |
|---|---|---|---|
| Circle | `#E7C694` | `#E7C694` | `#E7C694` |
| Rounded square | `#A3B690` | `#86A36F` | `#86A36F` |
| Overlap | `#2E3A2F` | `#F8F6EE` | `#F8F6EE` |
| Wordmark | `#2E3A2F` | `#EDEBE4` | |
| Background | | | `#2E3A2F` |

The source files are kept outside the repository, in a local `hora/logo/` folder: the mark (`hora-zeichen.svg`, `hora-zeichen-dunkel.svg`), mark with wordmark (`hora-logo.svg`, `hora-logo-dunkel.svg`), the full-bleed app icon (`hora-app-icon.svg`), a favicon that switches the square and overlap colours with `prefers-color-scheme` (`hora-favicon.svg`) and PNG exports. The lilac set that was used until September 2026 is kept next to them in `hora/archiv/logo-lila/`.

Where the logo is used:

- In-app logo: `flutter_app/assets/logo.png`, the transparent mark at 1024 px.
- Native icons: `cd flutter_app && dart run flutter_launcher_icons` generates them from `flutter_app/assets/icon/`. `app_icon.png` is full-bleed (iOS, Android legacy, web), `app_icon_foreground.png` is the Android adaptive foreground on `#2E3A2F`, `app_icon_rounded.png` goes to Windows and `app_icon_macos.png` has the macOS shape with margin and shadow. The config in `pubspec.yaml` covers Android, iOS, web, Windows and macOS.
- Flask: `app/static/images/logo.png` (sidebar, apps page), `app/static/favicon.png` (64 px), `app/static/images/icons/icon-*.png` (PWA, full-bleed). The apple touch icons point at `icon-192.png`, because iOS fills transparent touch icons with black. The service worker (`/sw.js`, from `app/templates/app/sw.js`) caches only the new UI's files and names its caches after their digest, so new icons need no manual cache bump.
- iOS launch image: `flutter_app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{,@2x,@3x}.png`.
- Electron: `desktop/resources/icon.png` (macOS shape, 512 px) and `icon.ico` (16 to 256 px), the Linux icon set `desktop/resources/icons/` (16 to 512 px, scaled from `icon.png`) and the tray marks in `desktop/resources/tray/` (the mark alone, pine overlap for light taskbars, chalk overlap for dark ones).
- Promo video: `promo-video/public/logo.png`, the dark-background variant at 1024 px.
- Landing page: `landing-page/public/logo.svg` (navbar, footer watermark, `logoUrl` in `src/content/company.json`) and `landing-page/public/favicon.svg`.

Still to do:

- Electron installers for Windows and Linux: the backend is frozen with PyInstaller on each platform, so CI builds them on release (`.github/workflows/release.yml`). The macOS app build waits for the name decision.
- Promo video renders.
- Replace screenshots that show the old logo: `landing-page/public/dashboard.png`, `landing-page/public/screenshots/`, `promo-video/public/screenshots/`.
- `landing-page/public/icon.svg` and `placeholder-logo.*` are not referenced by the landing sources and can go.

## Colours

The current UI palette was derived in OKLCH from the lilac logo used until September 2026, with its colours as fixed steps: violet 300 `#B7A6F6`, violet 800 `#3D2E7C`, violet 900 `#2A2150` (its icon background) and mint 200 `#8FE0C0`. Violet means act (buttons, links, selection, focus), mint means done (success, progress), indigo gives depth (pressed states, splash), and the slightly violet neutrals carry surfaces and text. The logo now uses the palette of the redesign; these UI colours stay until the redesign replaces them.

| Token | Light | Dark |
|---|---|---|
| Primary | `#7353CD` | `#7353CD` in Flutter, `#9580E8` on the web |
| Primary hover | `#5538A0` | `#B7A6F6` |
| Accent | `#9580E8` | `#9580E8` |
| Background | `#FBFAFF` | `#14131A` |
| Surface | `#FFFFFF` | `#1D1C24` |
| Border | `#DCDBE4` | `#302F3B` |
| Text | `#1D1C24` | `#ECECF3` |
| Text 2 | `#575665` | `#C7C6D1` |
| Text 3 | `#686775` | `#9E9DAA` |
| Success | `#1D9D77` | `#1D9D77` |

Why `#7353CD`: the colour research recommends `#6847BF` in light mode and the logo lilac `#B7A6F6` in dark mode. The Flutter screens use `AppTheme.primaryColor` directly in about 350 places in both modes, so one value has to work on both backgrounds. `#7353CD` gives 5.46:1 on white (white text on it 5.46:1) and 3.38:1 on the dark background, slightly more than the old Signal Blue (3.27:1). Moving the screens to `Theme.of(context).colorScheme` would allow the split values.

Where the colours live: `flutter_app/lib/theme.dart` (`AppTheme`), `flutter_app/lib/widgets/app_background.dart`, the navigation bar colours in `flutter_app/lib/main.dart`, `launch_background` in `flutter_app/android/app/src/main/res/values/colors.xml`, the loading screen in `flutter_app/web/index.html`, the variable blocks at the top of `app/static/css/hub.css`, the sidebar highlight in `app/templates/hub/base.html`, `theme_color` in both manifests and the `theme-color` meta tags, and the `brand` colours and gradients in `landing-page/tailwind.config.js`. Tailwind is not installed in the landing page: `public/tailwind.css` and `compiled-tailwind.css` are prebuilt and were changed by value.

Kept on purpose: category and subject colours (school blue, grade colours, the subject colour choices, the mousepad pen colours) and the warning and error colours. The research suggests other hues for projects (`#8B5CF6`) and calendar (`#6366F1`), because both are now close to the primary.

Known limitation: dark web buttons with hardcoded white text on `#9580E8` reach 3.2:1, which is enough for bold or large text only. An `--on-accent` variable (`#2A2150` in dark mode) would fix that.

The research behind this, with competitor colours, sources and contrast tables, is kept outside the repository.
