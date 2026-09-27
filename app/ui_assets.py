# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import hashlib
from pathlib import Path

STATIC_ROOT = Path(__file__).resolve().parent / 'static'

UI_STATIC = [
    'app',
    'fonts/bricolage-grotesque.woff2',
    'fonts/OFL-Bricolage.txt',
    'css/tour.css',
    'js/tinte.js',
    'js/tour.js',
]


def ui_static_files():
    for entry in UI_STATIC:
        origin = STATIC_ROOT / entry
        if origin.is_dir():
            yield from sorted(path for path in origin.rglob('*') if path.is_file() and not path.name.startswith('.'))
        else:
            yield origin


def asset_digest():
    digest = hashlib.sha1()
    for path in ui_static_files():
        digest.update(str(path.relative_to(STATIC_ROOT)).encode('utf-8'))
        digest.update(path.read_bytes())
    return digest.hexdigest()[:10]


def asset_urls():
    return [f"/static/{path.relative_to(STATIC_ROOT).as_posix()}" for path in ui_static_files()]
