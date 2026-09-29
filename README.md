# Hora

**A unified productivity system that replaces five apps with one.** Hora brings together calendar, tasks, email, school management, transit routing, and more, all running locally on your device with zero cloud dependency.

I built Hora because I was tired of switching between separate apps for school, calendar, transit, and tasks. Instead of stitching together tools that don't talk to each other, I wanted one system that understands how these things connect: a cancelled class means a changed commute, a new homework assignment becomes a task with a deadline, and a calendar event shows the route to get there.

The product name lives in one place, see [brand/README.md](brand/README.md). Up to version 0.4 Hora was called Nexus.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-000000?style=flat&logo=flask&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-003B57?style=flat&logo=sqlite&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white)

---

## Download

The current version is 0.5.2. Get it from the [download page](https://hora-app.netlify.app/download) or from [GitHub Releases](https://github.com/LeonManuel0705/Hora/releases).

| Platform | What you get |
|:---|:---|
| macOS | Native app. Needs Python 3: on the first start the app creates its own Python environment and installs its packages once, which takes a few minutes. |
| Windows | Installer for the desktop app, backend included. |
| Linux | AppImage of the desktop app, backend included. |
| Android | Signed app package. |
| iPhone, iPad, browser | Web app, open it from the download page and add it to the home screen. |

On macOS the quickest way is the install script:

```bash
curl -sL https://hora-app.netlify.app/install-macos.sh | bash
```

It checks the checksum of the download, moves Hora into `/Applications` and removes the download quarantine. The app is signed ad hoc and not notarized, so without that step Gatekeeper would block the first launch.

**Coming from Nexus?** Your data comes along. On the first start the desktop apps take over the data of an existing Nexus installation.

**The assistant is a separate download.** No app ships the language model. The first time you open the assistant, Hora asks whether to install it. One click downloads the model (Gemma 4 E2B, about 3 GB) and, on desktops, the llama.cpp runtime for your system (11 to 32 MB), checks both against pinned SHA-256 sums and resumes where it stopped after an interruption. Afterwards the assistant runs entirely on the device. Settings → Assistent removes it again.

## What it does

Hora is a full stack productivity system spanning mobile, web and desktop, plus a landing page:

**Mobile App** (Flutter). Native Android/iOS app with offline first architecture. 17 screens covering dashboard, tasks, calendar, email, IServ, school timetable, transit routing, training tracker, notes, bookmarks, spaced repetition, a Pomodoro timer and an assistant. State management via Provider, local storage with SQLite and Hive, background sync via WorkManager.

**Web Dashboard** (Flask). Browser based interface with real time WebSocket updates, Google OAuth, and Progressive Web App support. Serves 200+ API endpoints backed by 16 SQLite tables and encrypted JSON files for school data. Handles Google Calendar sync, Gmail integration, IServ school system connectivity, CalDAV, and VBB transit routing with personalized recommendations.

**Desktop Apps**. On macOS the Flutter app runs natively and carries the Flask backend inside its bundle. On Windows and Linux an Electron shell bundles a frozen backend. Both serve the web dashboard on 127.0.0.1. The local assistant runs in a llama.cpp server that the backend installs on request and starts on 127.0.0.1 with a key of its own; it frees its memory after five idle minutes.

**Landing Page** (Vite). Marketing and download site in English and German, built as a static site for Netlify.

## Architecture decisions

* **Privacy first.** All data stays on device. Credentials are encrypted at rest using Fernet with PBKDF2 (600k iterations, salts per file). No telemetry, no accounts required.
* **Offline first.** The Flutter app works fully without network access. SQLite for structured data, Hive for encrypted key value storage. Background sync picks up when connectivity returns.
* **Security hardened.** OAuth CSRF protection, CSP headers with nonces on the new pages, SSRF validation on CalDAV/email hosts, CRLF header injection prevention, rate limiting, input sanitization across every endpoint. The local server only listens on 127.0.0.1, and the desktop apps check the backend with an HMAC handshake before they hand it a token.
* **Transparent migration.** `decrypt_file()` detects plaintext JSON and legacy encryption schemes, and re encrypts in place without user intervention.

## Project structure

```
Hora/
  flutter_app/          Flutter mobile/desktop app
    lib/
      screens/          17 app screens
      providers/        8 state management providers
      services/         28 services (sync, notifications, database, ...)
      widgets/          Reusable UI components
    scripts/            Build scripts for the apps
  app/                  Flask backend
    app.py              Main application (200+ route handlers)
    local_ai.py         On-demand install and runtime of the local assistant
    ui_pages.py         Pages of the new web interface
    database.py         SQLite/PostgreSQL models (16 tables)
    crypto_utils.py     Fernet encryption with auto-migration
    calendar_service.py CalDAV + macOS EventKit integration
    email_service.py    IMAP/SMTP email client
    iserv_service.py    German school system integration
    vbb_service.py      Berlin transit routing
    google_oauth.py     Google Calendar + Gmail OAuth
  landing-page/         Vite marketing site
  site/                 Built landing page, published to Netlify
  desktop/              Electron shell for Windows/Linux
  brand/                Product name (brand.json) and logo locations
  scripts/              Backend freeze and brand scripts
  tests/                Backend test suite
```

## Getting started

### Mobile app

```bash
cd flutter_app
flutter pub get
flutter run
```

### Web dashboard

```bash
./setup.sh        # initial setup
./start.sh         # starts on http://127.0.0.1:5050
```

### Landing page

```bash
cd landing-page
npm install
npm run dev        # http://localhost:4321
npm run build      # builds into dist/, copy it to ../site/ to publish
```

### Environment variables

Copy `.env.example` to `.env`. For Google Calendar and Gmail fill in:

```
GOOGLE_CLIENT_ID=<client id>
GOOGLE_CLIENT_SECRET=<client secret>
GOOGLE_PROJECT_ID=<project id>
```

Leave `SECRET_KEY` unset. Hora then generates a random key in `data/.secret_key` on the first start. Set it only to share one key across machines, and then use a real random value. Setting `DATABASE_URL` switches the backend from SQLite to PostgreSQL.

### Building the apps

```bash
flutter_app/scripts/build_macos.sh     # macOS app with the backend inside

bash scripts/build_backend.sh          # frozen backend, built on the target platform
cd desktop
npm install                            # needs Node 22.12 or newer
npm run build:win                      # per-user installer for Windows
npm run build:linux                    # AppImage and .deb
```

The build scripts copy the frozen backend into the package and stop if it is missing. `npm start` in `desktop/` runs the shell against the Python source of this checkout (`venv/` in the repo root, or `HUB_DEV_PYTHON`). Unpackaged runs also read `HUB_DEV_PORT`, `HUB_DEV_APP_DATA`, `HUB_DEV_UPDATE_URL` and `HUB_DEV_LEGACY_DOCUMENTS`, so a test run leaves the real port, profile and Documents folder alone. `npm test` checks the shell's URL and version rules and the takeover of old data. With `HUB_TEST_PYTHON` set to a Python that has python-dotenv and cryptography, it also checks the takeover against python-dotenv and the backend's key handling.

On Windows and Linux the first start looks for data from the previous names in `brand/brand.json` under `Documents/<name>`, both where the old app kept it and where Windows or XDG puts the Documents folder. If the new profile holds no user data yet (no data folder, or only what a start created by itself), the app asks before it copies anything. It copies `data/` into the profile and writes the key the old app encrypted with into `data/.secret_key`: a `SECRET_KEY` from the environment, else one from `.env` or `.flaskenv` as Flask found them, else the old `data/.secret_key`. If that key is unclear, cannot be stored exactly, is missing or is one the backend refuses, and data is encrypted with it, it stops with a message instead of guessing and offers to take over everything except the encrypted files. The old folder is only ever read. After "Neu anfangen" the question comes back once the profile's `data` folder is removed while the app is closed. The packaged backend runs with `FLASK_SKIP_DOTENV=1` and `PYTHON_DOTENV_DISABLED=1`, so no `.env` file can change its key or settings.

## Tech stack

| Layer | Technology |
|:---|:---|
| Mobile | Flutter, Dart, SQLite, Hive, Provider, WorkManager |
| Backend | Flask, Flask SocketIO, SQLite/PostgreSQL, Fernet |
| Integrations | Google Calendar API, Gmail API, IServ, CalDAV, VBB |
| Desktop | Flutter (macOS), Electron and electron builder (Windows, Linux) |
| Landing page | Vite, DOMPurify |
| CI | GitHub Actions (pytest, flutter analyze, flutter test, release builds) |

## Deployment

**Landing page** deploys to Netlify as a static site (publish directory: `site/`).

**Backend** runs locally, inside the desktop apps or through `start.sh`.

**Releases** start with a version tag: pushing `v*` runs the release workflow in GitHub Actions, which builds the release packages.

## Tests

```bash
pip install pytest
python -m pytest tests/ -v
cd flutter_app && flutter test
```

## License

Hora is dual licensed.

**[AGPL-3.0](LICENSE)** for everyone. Free to use, study, modify and run. If you
modify Hora and let other people use your modified version over a network,
section 13 requires you to offer them your source. Running it unmodified triggers
nothing.

**[Commercial license](COMMERCIAL-LICENSE.md)** for schools, school authorities
and service providers that need private modifications, closed redistribution or
an operated service with support and a GDPR data processing agreement.

Copyright (C) 2026 Leon Manuel Töpper. See [NOTICE](NOTICE) for the full
statement, including the license history: Hora was published under the MIT
License until 2026-09-20 and that offer has been withdrawn.

Contributions require the [CLA](licensing/CLA.md), which is what keeps the dual
license possible. See [CONTRIBUTING.md](CONTRIBUTING.md).
