# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import re
from pathlib import Path

from app import ui_data

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'app' / 'static' / 'app' / 'js' / 'reminders.js'


def reminder_defaults():
    block = SOURCE.read_text(encoding='utf-8').split('export const CATEGORY_DEFAULTS = {', 1)[1].split('};', 1)[0]
    defaults = {}
    for key, body in re.findall(r'(\w+): \{([^}]*)\}', block):
        lead = re.search(r'lead: (\d+)', body)
        defaults[key] = {'on': 'on: true' in body, 'lead': int(lead.group(1)) if lead else None}
    return defaults


def test_reminders_start_from_the_same_defaults_as_the_settings_page():
    expected = {
        item['key']: {'on': item['on'], 'lead': item.get('lead')}
        for item in ui_data.NOTIFY_DEFAULTS['categories']
        if item['key'] != 'pomodoro'
    }
    assert reminder_defaults() == expected


def test_every_page_starts_the_reminders():
    main = (ROOT / 'app' / 'static' / 'app' / 'js' / 'main.js').read_text(encoding='utf-8')
    assert 'import { initReminders } from "./reminders.js";' in main
    assert re.search(r'^initReminders\(\);$', main, re.M)


def test_the_phone_app_ships_the_same_reminders():
    copy = ROOT / 'flutter_app' / 'assets' / 'ui' / 'static' / 'app' / 'js' / 'reminders.js'
    assert copy.read_text(encoding='utf-8') == SOURCE.read_text(encoding='utf-8')
