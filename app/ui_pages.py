# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import json
import time
from datetime import date, datetime, timedelta

from flask import Blueprint, jsonify, render_template, request

from . import database as db
from . import transit_service
from . import ui_data

bp = Blueprint('ui', __name__)

STORE_KEYS = {
    'app-timetable-edits', 'app-block-times', 'app-ab-swap', 'app-ab-weeks', 'app-subjects', 'app-teachers', 'app-rooms',
    'app-settings', 'app-motion', 'app-theme-choice', 'app-single-keys', 'app-task-filter', 'app-cal-view',
}

PAGES = {
    'home': ('/hub', 'app/home.html'),
    'tasks': ('/hub/tasks', 'app/tasks.html'),
    'calendar': ('/hub/calendar', 'app/calendar.html'),
    'school': ('/hub/school', 'app/school.html'),
    'vbb': ('/hub/vbb', 'app/transit.html'),
    'email': ('/hub/email', 'app/email.html'),
    'settings': ('/hub/settings', 'app/settings.html'),
}


def script_json(value):
    text = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    return (text.replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
            .replace('\u2028', '\\u2028').replace('\u2029', '\\u2029'))


def ui_settings(store):
    choice = store.get('app-theme-choice')
    if choice not in ('light', 'dark'):
        choice = 'auto' if 'app-theme-choice' in store or db.get_user_theme() not in ('light', 'dark') else db.get_user_theme()
    motion = 'minimal' if store.get('app-motion') == 'minimal' else 'calm'
    return {'theme': choice, 'motion': motion}


def pinned_day():
    try:
        return date.fromisoformat(request.args.get('datum', ''))
    except ValueError:
        return None


def render_page(active):
    _, template = PAGES[active]
    store = db.get_ui_store()
    day = pinned_day()
    now = datetime.combine(day, datetime.now().time()) if day else datetime.now()
    data = ui_data.build(active, store, now)
    return render_template(
        template,
        active=active,
        ui=ui_settings(store),
        data_json=script_json(data),
        store_json=script_json(store),
        asset_version=int(time.time()),
    )


def _page_view(active):
    def view():
        return render_page(active)
    view.__name__ = f'ui_page_{active}'
    return view


for _active, (_path, _template) in PAGES.items():
    bp.add_url_rule(_path, view_func=_page_view(_active))


@bp.route('/api/ui/store/<key>', methods=['PUT', 'DELETE'])
def store_value(key):
    if key not in STORE_KEYS:
        return jsonify({'success': False, 'error': 'Unbekannter Schlüssel'}), 404
    if request.method == 'DELETE':
        db.delete_ui_value(key)
        ui_data.mirror_store(key, None)
        return jsonify({'success': True})
    if not request.is_json:
        return jsonify({'success': False, 'error': 'JSON erwartet'}), 415
    value = request.get_json(silent=True)
    if value is None and request.get_data(as_text=True).strip() != 'null':
        return jsonify({'success': False, 'error': 'Ungültiges JSON'}), 400
    try:
        db.save_ui_value(key, value)
    except ValueError:
        return jsonify({'success': False, 'error': 'Zu groß'}), 413
    ui_data.mirror_store(key, value)
    return jsonify({'success': True})


@bp.route('/api/ui/transit/<action>')
def transit(action):
    result, status = transit_service.handle(action, request.args)
    return jsonify(result), status


def _payload():
    if not request.is_json:
        return None
    value = request.get_json(silent=True)
    return value if isinstance(value, dict) else None


def _error(message, status=400):
    return jsonify({'success': False, 'error': message}), status


def _text(value, limit):
    return str(value or '').strip()[:limit]


def _subjects():
    return ui_data.school_setup(db.get_timetable_settings() or {})['subjects']


def _task_columns(payload, subjects, creating):
    columns = {}
    if 'title' in payload or creating:
        title = _text(payload.get('title'), 300)
        if not title:
            raise ValueError('Titel fehlt')
        columns['title'] = title
    if 'subject' in payload:
        columns['subject'] = payload['subject'] if payload['subject'] in subjects else None
    if 'date' in payload:
        columns['due_date'] = ui_data.iso_day(payload['date'])
    if 'someday' in payload:
        columns['someday'] = 1 if payload['someday'] else 0
    if 'dueTime' in payload:
        columns['due_time'] = ui_data.clock(payload['dueTime'])
    if 'minutes' in payload:
        minutes = payload['minutes']
        columns['minutes'] = minutes if isinstance(minutes, int) and 0 < minutes <= 1440 else None
    if 'priority' in payload:
        columns['priority'] = 'high' if payload['priority'] else 'medium'
    if 'repeat' in payload:
        columns['repeat_type'] = payload['repeat'] if payload['repeat'] in ui_data.REPEATS else 'none'
    if 'notes' in payload:
        columns['description'] = _text(payload.get('notes'), 5000)
    if 'deadline' in payload:
        columns['deadline_ref'] = _text(payload.get('deadline'), 60) or None
    if 'source' in payload:
        columns['source'] = 'iserv' if payload['source'] == 'iserv' else 'own'
    return columns


def _task_row(task_id):
    conn = db.get_connection()
    cursor = conn.cursor()
    db._execute(cursor, 'SELECT * FROM hub_tasks WHERE id = ?', (task_id,))
    row = db._fetchone_dict(cursor)
    conn.close()
    return row


@bp.route('/api/ui/tasks', methods=['POST'])
def create_task():
    payload = _payload()
    if payload is None:
        return _error('JSON erwartet')
    subjects = _subjects()
    try:
        columns = _task_columns(payload, subjects, creating=True)
    except ValueError as error:
        return _error(str(error))
    done = bool(payload.get('done'))
    columns.setdefault('priority', 'medium')
    columns.setdefault('repeat_type', 'none')
    columns['completed'] = 1 if done else 0
    columns['completed_at'] = datetime.now().isoformat() if done else None
    names = list(columns)
    conn = db.get_connection()
    cursor = conn.cursor()
    db._execute(cursor, f"INSERT INTO hub_tasks ({', '.join(names)}) VALUES ({', '.join('?' for _ in names)})", [columns[name] for name in names])
    task_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'task': ui_data.task_view(_task_row(task_id), subjects)})


@bp.route('/api/ui/tasks/<int:task_id>', methods=['PATCH', 'DELETE'])
def change_task(task_id):
    if not _task_row(task_id):
        return _error('Aufgabe nicht gefunden', 404)
    if request.method == 'DELETE':
        db.delete_hub_task(task_id)
        return jsonify({'success': True})
    payload = _payload()
    if payload is None:
        return _error('JSON erwartet')
    subjects = _subjects()
    try:
        columns = _task_columns(payload, subjects, creating=False)
    except ValueError as error:
        return _error(str(error))
    if 'done' in payload:
        columns['completed'] = 1 if payload['done'] else 0
        columns['completed_at'] = datetime.now().isoformat() if payload['done'] else None
    if columns:
        assignments = ', '.join(f'{name} = ?' for name in columns)
        conn = db.get_connection()
        cursor = conn.cursor()
        db._execute(cursor, f'UPDATE hub_tasks SET {assignments}, updated_at = CURRENT_TIMESTAMP WHERE id = ?', [*columns.values(), task_id])
        conn.commit()
        conn.close()
    return jsonify({'success': True, 'task': ui_data.task_view(_task_row(task_id), subjects)})


def _deadline_ref(ref):
    prefix, _, item_id = str(ref).partition('-')
    if prefix not in ui_data.DEADLINE_KINDS or not item_id:
        return None, None
    return prefix, item_id


def _deadline_payload(prefix, payload, item, subjects, creating):
    if 'title' in payload or creating:
        title = _text(payload.get('title'), 300)
        if not title:
            raise ValueError('Titel fehlt')
        item['title'] = title
    if 'subject' in payload:
        item['subject_id'] = payload['subject'] if payload['subject'] in subjects else ''
    if 'date' in payload or creating:
        when = ui_data.iso_day(payload.get('date'))
        if not when:
            raise ValueError('Datum fehlt')
        item['due_date' if prefix == 'hw' else 'date'] = when
    if 'detail' in payload:
        item['notes' if prefix == 'hw' else 'topics'] = _text(payload.get('detail'), 2000)
    if prefix != 'hw' and 'time' in payload:
        item['time'] = ui_data.clock(payload.get('time')) or ''
    if prefix == 'hw' and 'status' in payload:
        item['completed'] = payload['status'] == 'abgegeben'


@bp.route('/api/ui/deadlines', methods=['POST'])
def create_deadline():
    payload = _payload()
    if payload is None:
        return _error('JSON erwartet')
    prefix = {'Hausaufgabe': 'hw', 'Test': 'test', 'Klausur': 'exam'}.get(payload.get('kind'))
    if not prefix:
        return _error('Unbekannte Art')
    school = ui_data.school_setup(db.get_timetable_settings() or {})
    item = {'id': ui_data.short_id(), 'created_at': datetime.now().isoformat()}
    if prefix == 'hw':
        item.update({'subject_id': '', 'notes': '', 'completed': False})
    else:
        item.update({'subject_id': '', 'time': '', 'topics': ''})
    try:
        _deadline_payload(prefix, payload, item, school['subjects'], creating=True)
    except ValueError as error:
        return _error(str(error))
    name = ui_data.DEADLINE_KINDS[prefix][0]
    try:
        ui_data.modify_list(name, lambda items: items.append(item))
    except ui_data.StoreError:
        return _error('Die Schuldaten ließen sich nicht lesen', 500)
    view = ui_data.deadline_view(prefix, item, school, date.today())
    return jsonify({'success': True, 'deadline': view})


@bp.route('/api/ui/deadlines/<ref>', methods=['PATCH', 'DELETE'])
def change_deadline(ref):
    prefix, item_id = _deadline_ref(ref)
    if not prefix:
        return _error('Unbekannter Eintrag', 404)
    name = ui_data.DEADLINE_KINDS[prefix][0]
    school = ui_data.school_setup(db.get_timetable_settings() or {})
    payload = None
    if request.method == 'PATCH':
        payload = _payload()
        if payload is None:
            return _error('JSON erwartet')

    def change(items):
        for index, item in enumerate(items):
            if str(item.get('id')) == item_id:
                if payload is None:
                    items.pop(index)
                    return {}
                _deadline_payload(prefix, payload, item, school['subjects'], creating=False)
                item['updated_at'] = datetime.now().isoformat()
                return item
        return None

    try:
        found = ui_data.modify_list(name, change)
    except ui_data.StoreError:
        return _error('Die Schuldaten ließen sich nicht lesen', 500)
    except ValueError as error:
        return _error(str(error))
    if found is None:
        return _error('Eintrag nicht gefunden', 404)
    if payload is None:
        return jsonify({'success': True})
    return jsonify({'success': True, 'deadline': ui_data.deadline_view(prefix, found, school, date.today())})


@bp.route('/api/ui/grades', methods=['POST'])
def create_grade():
    payload = _payload()
    if payload is None:
        return _error('JSON erwartet')
    subjects = _subjects()
    points = payload.get('points')
    if payload.get('subject') not in subjects:
        return _error('Fach fehlt')
    if not isinstance(points, int) or not 0 <= points <= 15:
        return _error('Punkte fehlen')
    kind = payload.get('type') if payload.get('type') in ('klausur', 'test', 'muendlich', 'sonstiges') else 'sonstiges'
    item = {
        'id': ui_data.full_id(),
        'subject_id': payload['subject'],
        'points': points,
        'type': kind,
        'date': ui_data.iso_day(payload.get('date')) or date.today().isoformat(),
        'description': _text(payload.get('title'), 300),
        'semester': _text(payload.get('semester'), 12) or 'Q1',
        'grade_system': 'points',
        'value': None,
        'created_at': datetime.now().isoformat(),
    }
    try:
        ui_data.modify_list('grades', lambda items: items.append(item))
    except ui_data.StoreError:
        return _error('Die Noten ließen sich nicht lesen', 500)
    return jsonify({'success': True, 'grade': {'id': f"g-{item['id']}", 'subject': item['subject_id'], 'points': points, 'type': kind, 'semester': item['semester'], 'date': item['date'], 'title': item['description']}})


@bp.route('/api/ui/grades/<ref>', methods=['DELETE'])
def delete_grade(ref):
    if not str(ref).startswith('g-'):
        return _error('Unbekannte Note', 404)
    grade_id = ref[2:]

    def change(items):
        before = len(items)
        items[:] = [item for item in items if str(item.get('id')) != grade_id]
        return before != len(items)

    try:
        removed = ui_data.modify_list('grades', change)
    except ui_data.StoreError:
        return _error('Die Noten ließen sich nicht lesen', 500)
    return jsonify({'success': True}) if removed else _error('Note nicht gefunden', 404)


EVENT_CATEGORIES = {'school': 'school', 'training': 'training', 'private': 'personal'}


def _event_payload(payload, item, creating):
    if 'title' in payload or creating:
        title = _text(payload.get('title'), 300)
        if not title:
            raise ValueError('Titel fehlt')
        item['title'] = title
    if 'date' in payload or creating:
        when = ui_data.iso_day(payload.get('date'))
        if not when:
            raise ValueError('Datum fehlt')
        item['date'] = when
    if 'endDate' in payload:
        item['end_date'] = ui_data.iso_day(payload.get('endDate')) or ''
    if 'start' in payload:
        item['time'] = ui_data.clock(payload.get('start')) or ''
    if 'end' in payload:
        item['end_time'] = ui_data.clock(payload.get('end')) or ''
    if 'place' in payload:
        item['location'] = _text(payload.get('place'), 300)
    if 'notes' in payload:
        item['description'] = _text(payload.get('notes'), 5000)
    if 'kind' in payload:
        item['category'] = EVENT_CATEGORIES.get(payload.get('kind'), 'personal')


@bp.route('/api/ui/events', methods=['POST'])
def create_event():
    payload = _payload()
    if payload is None:
        return _error('JSON erwartet')
    item = {'id': ui_data.full_id(), 'time': '', 'end_date': '', 'end_time': '', 'category': 'personal', 'description': '', 'location': '', 'created_at': datetime.now().isoformat()}
    try:
        _event_payload(payload, item, creating=True)
    except ValueError as error:
        return _error(str(error))
    try:
        ui_data.modify_list('calendar', lambda items: items.append(item))
    except ui_data.StoreError:
        return _error('Der Kalender ließ sich nicht lesen', 500)
    return jsonify({'success': True, 'event': ui_data.event_view(item)})


@bp.route('/api/ui/events/<ref>', methods=['PATCH', 'DELETE'])
def change_event(ref):
    if not str(ref).startswith('loc-'):
        return _error('Nur eigene Termine lassen sich hier ändern', 404)
    event_id = ref[4:]
    payload = None
    if request.method == 'PATCH':
        payload = _payload()
        if payload is None:
            return _error('JSON erwartet')

    def change(items):
        for index, item in enumerate(items):
            if str(item.get('id')) == event_id:
                if payload is None:
                    items.pop(index)
                    return {}
                _event_payload(payload, item, creating=False)
                item['updated_at'] = datetime.now().isoformat()
                return item
        return None

    try:
        found = ui_data.modify_list('calendar', change)
    except ui_data.StoreError:
        return _error('Der Kalender ließ sich nicht lesen', 500)
    except ValueError as error:
        return _error(str(error))
    if found is None:
        return _error('Termin nicht gefunden', 404)
    if payload is None:
        return jsonify({'success': True})
    return jsonify({'success': True, 'event': ui_data.event_view(found)})


@bp.route('/api/ui/notes', methods=['POST'])
def create_note():
    payload = _payload()
    if payload is None:
        return _error('JSON erwartet')
    title = _text(payload.get('title'), 300)
    if not title:
        return _error('Titel fehlt')
    note = {
        'id': ui_data.full_id(),
        'type': 'idea' if payload.get('type') == 'idea' else 'note',
        'title': title,
        'content': _text(payload.get('details'), 5000),
        'created_at': datetime.now().isoformat(),
    }
    try:
        ui_data.modify_list('notes', lambda items: items.append(note))
    except ui_data.StoreError:
        return _error('Die Notizen ließen sich nicht lesen', 500)
    return jsonify({'success': True, 'note': {'id': note['id']}})


SYNCED_KIND_WORDS = (
    ('training', ('training', 'sport', 'gym', 'fitness', 'schwimm', 'verein')),
    ('school', ('schule', 'school', 'iserv', 'kurs', 'uni', 'klasse')),
)


def _synced_kind(*texts):
    text = ' '.join(str(item or '') for item in texts).casefold()
    for kind, words in SYNCED_KIND_WORDS:
        if any(word in text for word in words):
            return kind
    return 'private'


def _synced_google(start, end):
    from .google_oauth import fetch_google_calendar_events, load_tokens
    if not load_tokens():
        return None
    result = fetch_google_calendar_events(start_date=start, end_date=end, days_ahead=180)
    if not result.get('success'):
        return None
    events = []
    for item in result.get('events', []):
        day = ui_data.iso_day(item.get('start_date'))
        if not day:
            continue
        last = ui_data.iso_day(item.get('end_date'))
        if item.get('all_day') and last:
            last = (date.fromisoformat(last) - timedelta(days=1)).isoformat()
        view = {
            'id': f"g-{item.get('calendar_id', '')}-{item.get('id', '')}",
            'date': day,
            'start': None if item.get('all_day') else ui_data.clock(item.get('start_time')),
            'end': None if item.get('all_day') else ui_data.clock(item.get('end_time')),
            'title': str(item.get('title') or 'Termin'),
            'place': str(item.get('location') or ''),
            'kind': _synced_kind(item.get('calendar'), item.get('title')),
            'notes': str(item.get('description') or '')[:2000],
            'source': 'dem Google-Kalender',
        }
        if last and last > day:
            view['endDate'] = last
        events.append(view)
    return events


def _synced_macos(start, end):
    from .calendar_service import get_macos_calendar_events
    days = max(1, min(365, (date.fromisoformat(end) - date.today()).days))
    result = get_macos_calendar_events(days)
    if not result.get('success'):
        return None
    events = []
    for index, item in enumerate(result.get('events', [])):
        day = ui_data.iso_day(item.get('date'))
        if not day or day < start or day > end:
            continue
        events.append({
            'id': f'm-{day}-{index}',
            'date': day,
            'start': ui_data.clock(item.get('time')),
            'end': None,
            'title': str(item.get('title') or 'Termin'),
            'place': str(item.get('location') or ''),
            'kind': _synced_kind(item.get('calendar'), item.get('title')),
            'notes': str(item.get('description') or '')[:2000],
            'source': 'dem Mac-Kalender',
        })
    return events


@bp.route('/api/ui/events/synced')
def synced_events():
    today = date.today()
    start = ui_data.iso_day(request.args.get('start')) or (today - timedelta(days=42)).isoformat()
    end = ui_data.iso_day(request.args.get('end')) or (today + timedelta(days=120)).isoformat()
    if end < start or (date.fromisoformat(end) - date.fromisoformat(start)).days > 400:
        return _error('Zeitraum ungültig')
    for loader in (_synced_google, _synced_macos):
        try:
            events = loader(start, end)
        except Exception:
            events = None
        if events is not None:
            for item in events:
                item['synced'] = True
            return jsonify({'success': True, 'events': events})
    return jsonify({'success': True, 'events': []})


@bp.route('/api/ui/places/<key>', methods=['PUT', 'DELETE'])
def save_place(key):
    if key not in ('home', 'school'):
        return _error('Unbekannter Ort', 404)
    from .vbb_service import get_vbb_service
    service = get_vbb_service()
    if request.method == 'DELETE':
        service.delete_known_location(key)
        return jsonify({'success': True})
    payload = _payload()
    if payload is None:
        return _error('JSON erwartet')
    try:
        lat, lon = float(payload.get('lat')), float(payload.get('lon'))
    except (TypeError, ValueError):
        return _error('Koordinaten fehlen')
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return _error('Koordinaten ungültig')
    name = _text(payload.get('name'), 120)
    if not name:
        return _error('Name fehlt')
    location = {
        'id': _text(payload.get('stop'), 120),
        'name': name,
        'type': 'stop' if payload.get('stop') else 'location',
        'latitude': lat,
        'longitude': lon,
        'address': _text(payload.get('area'), 120),
    }
    service.save_known_location(key, location)
    return jsonify({'success': True, 'place': ui_data.place_view('Zuhause' if key == 'home' else 'Schule', location)})
