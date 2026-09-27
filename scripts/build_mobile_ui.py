#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import filecmp
import hashlib
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / 'flutter_app' / 'assets' / 'ui'
PUBSPEC = ROOT / 'flutter_app' / 'pubspec.yaml'
SOURCE = ROOT / 'app' / 'static'
PAGES = {
    'home': 'app/home.html',
    'tasks': 'app/tasks.html',
    'calendar': 'app/calendar.html',
    'school': 'app/school.html',
    'vbb': 'app/transit.html',
    'email': 'app/email.html',
    'settings': 'app/settings.html',
}
STATIC = [
    'app',
    'fonts/bricolage-grotesque.woff2',
    'fonts/OFL-Bricolage.txt',
    'css/tour.css',
    'js/tinte.js',
    'js/tour.js',
]


class Nonce:
    csp_nonce = ''


def static_files():
    for entry in STATIC:
        origin = SOURCE / entry
        if origin.is_dir():
            yield from sorted(path for path in origin.rglob('*') if path.is_file() and not path.name.startswith('.'))
        else:
            yield origin


def asset_version():
    digest = hashlib.sha1()
    for path in static_files():
        digest.update(str(path.relative_to(SOURCE)).encode('utf-8'))
        digest.update(path.read_bytes())
    return digest.hexdigest()[:10]


def render_pages(out):
    os.environ.setdefault('HUB_DATA_DIR', tempfile.mkdtemp(prefix='ui-bundle-'))
    sys.path.insert(0, str(ROOT))
    from app.app import app
    version = asset_version()
    env = app.jinja_env
    for page, template in PAGES.items():
        html = env.get_template(template).render(
            brand_name='__APP_BRAND__',
            brand_repository='',
            active=page,
            ui={'theme': '__APP_THEME__', 'motion': '__APP_MOTION__'},
            data_json='__APP_DATA__',
            store_json='__APP_STORE__',
            asset_version=version,
            app_version='__APP_VERSION__',
            tour_auto=False,
            g=Nonce,
        )
        html = re.sub(r'\snonce=""', '', html)
        html = html.replace('data-tour-auto="0"', 'data-tour-auto="__APP_TOUR__"')
        html = html.replace('data-theme="light" data-theme-mode', 'data-theme="__APP_SCHEME__" data-theme-mode')
        (out / f'{page}.html').write_text(html, encoding='utf-8')


def copy_static(out):
    for path in static_files():
        target = out / path.relative_to(SOURCE)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)


def build(target):
    if target.exists():
        shutil.rmtree(target)
    (target / 'pages').mkdir(parents=True)
    (target / 'static').mkdir(parents=True)
    render_pages(target / 'pages')
    copy_static(target / 'static')


def listing(root):
    return sorted(str(path.relative_to(root)) for path in root.rglob('*') if path.is_file())


def differences(fresh, current):
    if not current.exists():
        return ['fehlt komplett']
    left, right = listing(fresh), listing(current)
    changed = sorted(set(left) ^ set(right))
    changed += [name for name in left if name in right and not filecmp.cmp(fresh / name, current / name, shallow=False)]
    return changed


def undeclared(root):
    declared = set(re.findall(r'^\s*-\s*(assets/ui/\S*/)\s*$', PUBSPEC.read_text(encoding='utf-8'), re.M))
    folders = {f"assets/ui/{path.parent.relative_to(root).as_posix()}/" for path in root.rglob('*') if path.is_file()}
    return sorted(folders - declared)


def report(missing):
    print('Diese Ordner fehlen in flutter_app/pubspec.yaml unter assets:')
    print('\n'.join(f'    - {name}' for name in missing))
    return 1


def main():
    if '--check' in sys.argv[1:]:
        with tempfile.TemporaryDirectory(prefix='ui-check-') as scratch:
            fresh = Path(scratch) / 'ui'
            build(fresh)
            changed = differences(fresh, TARGET)
            missing = undeclared(fresh)
        if changed:
            print('Die Handy-Oberfläche ist veraltet, bitte scripts/build_mobile_ui.py ausführen:')
            print('\n'.join(f'  {name}' for name in changed))
            return 1
        if missing:
            return report(missing)
        print('Die Handy-Oberfläche ist aktuell')
        return 0
    build(TARGET)
    print(f'{len(listing(TARGET))} Dateien nach {TARGET.relative_to(ROOT)} geschrieben')
    missing = undeclared(TARGET)
    return report(missing) if missing else 0


if __name__ == '__main__':
    sys.exit(main())
