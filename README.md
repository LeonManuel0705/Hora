# Hora

**A unified productivity system that replaces five apps with one.** Hora brings together calendar, tasks, email, school management, transit routing, and more, all running locally on your device with zero cloud dependency.

I built Hora because I was tired of switching between separate apps for school, calendar, transit, and tasks. Instead of stitching together tools that don't talk to each other, I wanted one system that understands how these things connect: a cancelled class means a changed commute, a new homework assignment becomes a task with a deadline, and a calendar event shows the route to get there.

The product name lives in one place, see [brand/README.md](brand/README.md).

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-000000?style=flat&logo=flask&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-003B57?style=flat&logo=sqlite&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white)

---

## What it does

Hora is a full stack productivity system spanning mobile, web and desktop, plus a landing page:

**Mobile App** (Flutter). Native Android/iOS app with offline first architecture. 17 screens covering dashboard, tasks, calendar, email, school timetable, transit routing, training tracker, notes, bookmarks, spaced repetition, and a Pomodoro timer. State management via Provider, local storage with SQLite and Hive, background sync via WorkManager.

**Web Dashboard** (Flask). Browser based interface with real time WebSocket updates, Google OAuth, and Progressive Web App support. Serves 180+ API endpoints backed by 15 SQLite tables and encrypted JSON files for school data. Handles Google Calendar sync, Gmail integration, IServ school system connectivity, CalDAV, and VBB transit routing with personalized recommendations.

**Landing Page** (Vite and Tailwind CSS v4). Marketing site with multi language support (EN/DE), screenshot gallery, smooth scroll animations, and static export for Netlify.

**Desktop App** (Electron). Bundles the Flask backend with a local HTTP server for Windows and Linux distribution.

## Architecture decisions

* **Privacy first.** All data stays on device. Credentials are encrypted at rest using Fernet with PBKDF2 (600k iterations, salts per file). No telemetry, no accounts required.
* **Offline first.** The Flutter app works fully without network access. SQLite for structured data, Hive for encrypted key value storage. Background sync picks up when connectivity returns.
* **Security hardened.** OAuth CSRF protection, CSP headers, SSRF validation on CalDAV/email hosts, CRLF header injection prevention, rate limiting, input sanitization across every endpoint.
* **Transparent migration.** `decrypt_file()` detects plaintext JSON and legacy encryption schemes, and re encrypts in place without user intervention.

## Project structure

```
Hora/
  flutter_app/          Flutter mobile/desktop app
    lib/
      screens/          17 app screens
      providers/        8 state management providers
      services/         20+ services (sync, notifications, database, ...)
      widgets/          Reusable UI components
  app/                  Flask backend
    app.py              Main application (200+ route handlers)
    database.py         SQLite/PostgreSQL models (15 tables)
    crypto_utils.py     Fernet encryption with auto-migration
    calendar_service.py CalDAV + macOS EventKit integration
    email_service.py    IMAP/SMTP email client
    iserv_service.py    German school system integration
    vbb_service.py      Berlin transit routing
    google_oauth.py     Google Calendar + Gmail OAuth
  landing-page/         Vite + Tailwind CSS marketing site
  desktop/              Electron wrapper for Windows/Linux
  brand/                Product name (brand.json) and logo locations
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
./start.sh         # starts on http://localhost:5050
```

### Landing page

```bash
cd landing-page
npm install
npm run dev        # http://localhost:3000
npm run build      # builds into dist/, copy it to ../site/ to publish
```

### Environment variables

Copy `.env.example` to `.env` and fill in:

```
SECRET_KEY=<secret key>
GOOGLE_CLIENT_ID=<client id>
GOOGLE_CLIENT_SECRET=<client secret>
GOOGLE_PROJECT_ID=<project id>
```

## Tech stack

| Layer | Technology |
|:---|:---|
| Mobile | Flutter, Dart, SQLite, Hive, Provider, WorkManager |
| Backend | Flask, Flask SocketIO, SQLite/PostgreSQL, Fernet |
| Integrations | Google Calendar API, Gmail API, IServ, CalDAV, VBB |
| Frontend | Vite, Tailwind CSS v4, DOMPurify |
| Desktop | Electron, electron builder |
| CI | GitHub Actions (pytest, flutter analyze) |

## Deployment

**Landing page** deploys to Netlify as a static site (publish directory: `site/`).

**Backend** deploys to Render using the included `render.yaml` blueprint with PostgreSQL.

## Tests

```bash
pip install pytest
python -m pytest tests/ -v
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
