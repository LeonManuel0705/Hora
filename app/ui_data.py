# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import colorsys
import copy
import json
import re
import threading
import uuid
import zlib
from datetime import date, datetime, timedelta

from . import brand
from . import database as db
from .crypto_utils import decrypt_file, encrypt_file
from .paths import DATA_DIR

HUES = {
    'rose': '#C1657E', 'ochre': '#9A6A1E', 'olive': '#6E6D0A', 'moss': '#669649', 'jade': '#0D7C59', 'teal': '#139999',
    'lake': '#0C7491', 'slate': '#5188CD', 'iris': '#635DAB', 'orchid': '#984979', 'brick': '#A34943', 'plum': '#A16FB8',
}
DEFAULT_BLOCKS = [('08:00', '09:30'), ('09:50', '11:20'), ('11:30', '13:00'), ('13:30', '15:00')]
DEFAULT_REFERENCE = '2026-01-12'
COURSE_TYPES = ('LK', 'GK', 'SK')
REPEATS = ('daily', 'weekly', 'monthly')
STATES = [
    ('BW', 'Baden-Württemberg'), ('BY', 'Bayern'), ('BE', 'Berlin'), ('BB', 'Brandenburg'), ('HB', 'Bremen'),
    ('HH', 'Hamburg'), ('HE', 'Hessen'), ('MV', 'Mecklenburg-Vorpommern'), ('NI', 'Niedersachsen'),
    ('NW', 'Nordrhein-Westfalen'), ('RP', 'Rheinland-Pfalz'), ('SL', 'Saarland'), ('SN', 'Sachsen'),
    ('ST', 'Sachsen-Anhalt'), ('SH', 'Schleswig-Holstein'), ('TH', 'Thüringen'),
]
DEADLINE_KINDS = {'hw': ('homework', 'Hausaufgabe'), 'test': ('tests', 'Test'), 'exam': ('exams', 'Klausur')}
EVENT_KINDS = {'school': 'school', 'training': 'training'}
NOTIFY_DEFAULTS = {
    'enabled': False,
    'sound': True,
    'quiet': {'from': '22:00', 'to': '07:00'},
    'categories': [
        {'key': 'lessons', 'label': 'Nächste Stunde', 'detail': 'Fach und Raum vor Beginn', 'on': True, 'lead': 10,
         'leads': [[5, '5 Min. vorher'], [10, '10 Min. vorher'], [15, '15 Min. vorher']]},
        {'key': 'tests', 'label': 'Tests und Klausuren', 'detail': 'mit Lernstoff', 'on': True, 'lead': 1,
         'leads': [[1, 'am Vortag'], [2, '2 Tage vorher'], [3, '3 Tage vorher'], [7, '1 Woche vorher']]},
        {'key': 'homework', 'label': 'Hausaufgaben', 'detail': 'vor der Abgabe', 'on': True, 'lead': 1,
         'leads': [[1, 'am Vortag'], [2, '2 Tage vorher']]},
        {'key': 'events', 'label': 'Termine', 'detail': 'aus dem Kalender', 'on': True, 'lead': 15,
         'leads': [[5, '5 Min. vorher'], [15, '15 Min. vorher'], [30, '30 Min. vorher'], [60, '1 Std. vorher']]},
        {'key': 'tasks', 'label': 'Aufgaben', 'detail': 'wenn sie fällig werden', 'on': True},
        {'key': 'pomodoro', 'label': 'Pomodoro', 'detail': 'Ende jeder Arbeits- und Pausenphase', 'on': True},
    ],
}

FILES = {
    'subjects': 'school_subjects.json',
    'homework': 'school_homework.json',
    'tests': 'school_tests.json',
    'exams': 'school_exams.json',
    'grades': 'school_grades.json',
    'calendar': 'school_calendar.json',
    'notes': 'quick_notes.json',
    'weather': 'weather_cache.json',
    'iserv': 'iserv_credentials.json',
    'google': 'google_tokens.json',
    'places': 'known_locations.json',
}

_cache = {}
_locks = {name: threading.Lock() for name in FILES}


class StoreError(Exception):
    pass


def _path(name):
    return DATA_DIR / FILES[name]


def _signature(path):
    stat = path.stat()
    return stat.st_mtime_ns, stat.st_size


def _read(name, strict=False):
    path = _path(name)
    try:
        signature = _signature(path)
    except OSError:
        return None
    hit = _cache.get(name)
    if hit and hit[0] == signature:
        return copy.deepcopy(hit[1])
    try:
        value = decrypt_file(path)
    except Exception as error:
        if strict:
            raise StoreError(name) from error
        return None
    try:
        signature = _signature(path)
    except OSError:
        pass
    _cache[name] = (signature, value)
    return copy.deepcopy(value)


def load_list(name):
    value = _read(name)
    return value if isinstance(value, list) else []


def load_dict(name):
    value = _read(name)
    return value if isinstance(value, dict) else {}


def modify_list(name, change):
    with _locks[name]:
        path = _path(name)
        if path.exists():
            items = _read(name, strict=True)
            if not isinstance(items, list):
                raise StoreError(name)
        else:
            items = []
        result = change(items)
        encrypt_file(items, path)
        _cache[name] = (_signature(path), copy.deepcopy(items))
        return result


def short_id():
    return uuid.uuid4().hex[:8]


def full_id():
    return str(uuid.uuid4())


def slug(text):
    text = str(text or '').lower()
    for a, b in (('ä', 'ae'), ('ö', 'oe'), ('ü', 'ue'), ('ß', 'ss')):
        text = text.replace(a, b)
    return re.sub(r'[^a-z0-9]+', '-', text).strip('-') or 'fach'


def _norm(name):
    return re.sub(r'\s+(lk|gk|sk)$', '', str(name or '').strip().casefold())


def _hex_rgb(color):
    match = re.fullmatch(r'#?([0-9a-fA-F]{6})', str(color or '').strip())
    if not match:
        return None
    value = match.group(1)
    return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))


def hue_for(color, seed):
    rgb = _hex_rgb(color)
    names = list(HUES)
    if rgb is None:
        return names[zlib.crc32(seed.encode('utf-8')) % len(names)]
    hue, saturation, _ = colorsys.rgb_to_hsv(*rgb)
    if saturation < 0.15:
        return 'slate'

    def distance(name):
        other, _, _ = colorsys.rgb_to_hsv(*_hex_rgb(HUES[name]))
        gap = abs(hue - other)
        return min(gap, 1 - gap)

    return min(names, key=distance)


def _short(name):
    clean = re.sub(r'[^A-Za-zÄÖÜäöüß]', '', _norm(name).title()) or 'Fach'
    return clean[:3]


def clock(value):
    match = re.fullmatch(r'\s*(\d{1,2}):(\d{2})(?::\d{2})?\s*', str(value or ''))
    if not match:
        return None
    hour, minute = int(match.group(1)), int(match.group(2))
    if hour > 23 or minute > 59:
        return None
    return f'{hour:02d}:{minute:02d}'


def iso_day(value):
    text = str(value or '').strip()[:10]
    try:
        return date.fromisoformat(text).isoformat()
    except ValueError:
        return None


def week_type(day, reference, ab_on):
    if not ab_on:
        return 'A'
    monday = day - timedelta(days=day.weekday())
    return 'A' if ((monday - date.fromisoformat(reference)).days // 7) % 2 == 0 else 'B'


def school_setup(settings):
    subjects = load_list('subjects')
    entries = db.get_timetable_entries()
    catalog = {}
    names = {}
    for item in subjects:
        key = str(item.get('id') or '').strip()
        name = str(item.get('name') or '').strip()
        if not key or not name or key in catalog:
            continue
        course = item.get('course_type') if item.get('course_type') in COURSE_TYPES else 'GK'
        label = f'{name} LK' if course == 'LK' and not name.endswith(' LK') else name
        catalog[key] = {'name': label, 'label': label, 'short': _short(name), 'hue': hue_for(item.get('color'), key), 'type': course}
        names.setdefault(_norm(name), key)
    for entry in entries:
        name = str(entry.get('subject') or '').strip()
        if not name or _norm(name) in names:
            continue
        key = f's-{slug(name)}'
        while key in catalog:
            key = f'{key}-x'
        course = entry.get('subject_type') if entry.get('subject_type') in COURSE_TYPES else 'GK'
        label = f'{name} LK' if course == 'LK' and not name.endswith(' LK') else name
        catalog[key] = {'name': label, 'label': label, 'short': _short(name), 'hue': hue_for(entry.get('color'), key), 'type': course}
        names[_norm(name)] = key

    periods = []
    for period in db.get_timetable_periods():
        start, end = clock(period.get('start_time')), clock(period.get('end_time'))
        number = period.get('period_number')
        if isinstance(number, int) and start and end and start < end:
            periods.append({'n': number, 'start': start, 'end': end})
    periods.sort(key=lambda block: block['n'])
    if not periods:
        highest = max((int(entry.get('block') or 0) for entry in entries), default=len(DEFAULT_BLOCKS))
        periods = [{'n': index + 1, 'start': start, 'end': end} for index, (start, end) in enumerate(DEFAULT_BLOCKS[:max(1, highest)])]
    known = {block['n'] for block in periods}

    timetable = {week: {str(day): [] for day in range(1, 6)} for week in ('A', 'B')}
    for entry in entries:
        try:
            day, block = int(entry.get('day')), int(entry.get('block'))
        except (TypeError, ValueError):
            continue
        key = names.get(_norm(entry.get('subject')))
        if not key or not 1 <= day <= 5 or block not in known:
            continue
        week = entry.get('week') or 'both'
        weeks = ('A', 'B') if week == 'both' else (week,) if week in ('A', 'B') else ()
        lesson = {'block': block, 'subject': key, 'room': str(entry.get('room') or '').strip()[:12], 'teacher': str(entry.get('teacher') or '').strip()}
        for name in weeks:
            day_list = [item for item in timetable[name][str(day)] if item['block'] != block]
            day_list.append(dict(lesson))
            timetable[name][str(day)] = sorted(day_list, key=lambda item: item['block'])

    reference = iso_day((settings or {}).get('reference_date')) or DEFAULT_REFERENCE
    ab_on = (settings or {}).get('has_ab_weeks') != 0
    subjects_view = {key: {k: v for k, v in info.items() if k != 'type'} for key, info in catalog.items()}
    courses = {key: {'type': info['type']} for key, info in catalog.items()}
    return {'subjects': subjects_view, 'courses': courses, 'blocks': periods, 'timetable': timetable, 'abReference': reference, 'abWeeks': ab_on}


def lesson_block(school, subject_key, day_iso):
    if not subject_key or not day_iso:
        return None
    day = date.fromisoformat(day_iso)
    if day.weekday() > 4:
        return None
    week = week_type(day, school['abReference'], school['abWeeks'])
    for lesson in school['timetable'][week][str(day.weekday() + 1)]:
        if lesson['subject'] == subject_key:
            return lesson['block']
    return None


def deadline_view(prefix, item, school, today):
    _, kind = DEADLINE_KINDS[prefix]
    when = iso_day(item.get('due_date') if prefix == 'hw' else item.get('date'))
    if not when:
        return None
    subject_key = str(item.get('subject_id') or '')
    if subject_key not in school['subjects']:
        subject_key = None
    detail = item.get('notes') if prefix == 'hw' else item.get('topics')
    view = {
        'id': f"{prefix}-{item.get('id')}",
        'kind': kind,
        'title': str(item.get('title') or kind),
        'subject': subject_key,
        'date': when,
        'detail': str(detail or ''),
        'status': 'abgegeben' if prefix == 'hw' and item.get('completed') else 'offen',
    }
    if prefix != 'hw' and clock(item.get('time')):
        view['time'] = clock(item.get('time'))
    block = lesson_block(school, subject_key, when)
    if block:
        view['block'] = block
    return view


def deadlines(school, today):
    horizon_back = (today - timedelta(days=14)).isoformat()
    result = []
    for prefix, (name, _) in DEADLINE_KINDS.items():
        for item in load_list(name):
            view = deadline_view(prefix, item, school, today)
            if not view:
                continue
            if view['date'] < horizon_back:
                continue
            if prefix == 'hw' and view['status'] == 'abgegeben' and view['date'] < today.isoformat():
                continue
            result.append(view)
    result.sort(key=lambda item: (item['date'], item.get('block') or 0))
    return result


def task_rows():
    conn = db.get_connection()
    cursor = conn.cursor()
    db._execute(cursor, 'SELECT * FROM hub_tasks')
    rows = db._fetchall_dict(cursor)
    conn.close()
    return rows


def _done_at(value):
    text = str(value or '')
    try:
        stamp = datetime.fromisoformat(text.replace('Z', '').replace(' ', 'T')[:26])
    except ValueError:
        return None, None
    return stamp.date().isoformat(), f'{stamp.hour}:{stamp.minute:02d}'


def task_view(row, subjects):
    due = iso_day(row.get('due_date'))
    due_time = clock(row.get('due_time'))
    subject_key = row.get('subject') if row.get('subject') in subjects else None
    view = {
        'id': str(row['id']),
        'title': str(row.get('title') or ''),
        'subject': subject_key,
        'date': due,
        'minutes': row.get('minutes') if isinstance(row.get('minutes'), int) and row.get('minutes') > 0 else 20,
        'priority': row.get('priority') == 'high',
        'done': bool(row.get('completed')),
        'notes': str(row.get('description') or ''),
        'source': row.get('source') or 'own',
    }
    if due_time:
        view['dueTime'] = f'{int(due_time[:2])}:{due_time[3:]}'
        view['anchor'] = f"bis {view['dueTime']}"
    if row.get('someday') and not due:
        view['someday'] = True
    if row.get('repeat_type') in REPEATS:
        view['repeat'] = row['repeat_type']
    if row.get('deadline_ref'):
        view['deadline'] = str(row['deadline_ref'])
    if view['done']:
        done_day, done_time = _done_at(row.get('completed_at'))
        view['doneDay'] = done_day
        view['doneAt'] = done_time
    return view


def tasks(subjects, today):
    today_iso = today.isoformat()
    recent = (today - timedelta(days=14)).isoformat()
    plan, pool = [], []
    for row in task_rows():
        view = task_view(row, subjects)
        if view['done']:
            done_day = view.get('doneDay') or ''
            if done_day == today_iso:
                plan.append(view)
            elif done_day >= recent:
                pool.append(view)
            continue
        if view.get('someday'):
            pool.append(view)
        elif not view['date'] or view['date'] <= today_iso:
            plan.append(view)
        else:
            pool.append(view)
    return plan, pool


def event_view(item):
    when = iso_day(item.get('date'))
    if not when:
        return None
    end_day = iso_day(item.get('end_date'))
    view = {
        'id': f"loc-{item.get('id')}",
        'date': when,
        'start': clock(item.get('time')),
        'end': clock(item.get('end_time')),
        'title': str(item.get('title') or 'Termin'),
        'place': str(item.get('location') or ''),
        'kind': EVENT_KINDS.get(item.get('category'), 'private'),
        'notes': str(item.get('description') or ''),
        'synced': False,
    }
    if end_day and end_day > when:
        view['endDate'] = end_day
    return view


def events(today):
    start = (today - timedelta(days=42)).isoformat()
    end = (today + timedelta(days=120)).isoformat()
    result = []
    for item in load_list('calendar'):
        view = event_view(item)
        if view and (view.get('endDate') or view['date']) >= start and view['date'] <= end:
            result.append(view)
    result.sort(key=lambda item: (item['date'], item['start'] or ''))
    return result


def holidays(today):
    start = (today - timedelta(days=400)).isoformat()
    end = (today + timedelta(days=400)).isoformat()
    result = []
    for row in db.get_holidays_for_date_range(start, end):
        when = iso_day(row.get('date'))
        if not when:
            continue
        end_day = iso_day(row.get('end_date'))
        result.append({
            'id': f"h-{row.get('id')}",
            'title': str(row.get('name') or 'Feiertag'),
            'date': when,
            'endDate': end_day if end_day and end_day > when else None,
            'type': 'ferien' if row.get('type') == 'schulferien' else 'feiertag',
        })
    return result


WEATHER_MAX_AGE = timedelta(minutes=30)
_weather_state = {'running': False}
_weather_lock = threading.Lock()


def weather_location(settings):
    try:
        value = json.loads((settings or {}).get('location_json') or 'null')
    except (TypeError, ValueError):
        return None
    if not isinstance(value, dict):
        return None
    lat, lon, city = value.get('lat'), value.get('lon'), str(value.get('city') or '').strip()
    if not city or not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
        return None
    return {'city': city, 'lat': lat, 'lon': lon}


def geocode(name):
    import requests
    response = requests.get(
        'https://geocoding-api.open-meteo.com/v1/search',
        params={'name': name, 'count': 1, 'language': 'de'},
        timeout=6,
    )
    response.raise_for_status()
    results = response.json().get('results') or []
    if not results or not isinstance(results[0], dict):
        return None
    first = results[0]
    lat, lon = first.get('latitude'), first.get('longitude')
    if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
        return None
    return {'city': str(first.get('name') or name).strip()[:80], 'lat': lat, 'lon': lon}


def refresh_weather(location):
    import requests
    response = requests.get(
        'https://api.open-meteo.com/v1/forecast',
        params={
            'latitude': location['lat'],
            'longitude': location['lon'],
            'current': 'temperature_2m,weather_code,wind_speed_10m',
            'hourly': 'temperature_2m,precipitation_probability',
            'daily': 'temperature_2m_max,temperature_2m_min,weather_code',
            'timezone': 'Europe/Berlin',
            'forecast_days': 2,
        },
        timeout=8,
    )
    response.raise_for_status()
    data = response.json()
    now = datetime.now()
    value = {
        'current': data.get('current'),
        'daily': data.get('daily'),
        'hourly': data.get('hourly'),
        'location': location,
        'timestamp': now.isoformat(),
        'fetched_at': now.strftime('%Y-%m-%d %H:%M:%S'),
    }
    path = _path('weather')
    with _locks['weather']:
        encrypt_file(value, path)
        _cache['weather'] = (_signature(path), copy.deepcopy(value))


def refresh_weather_soon(location):
    with _weather_lock:
        if _weather_state['running']:
            return
        _weather_state['running'] = True

    def run():
        try:
            refresh_weather(location)
        except Exception:
            pass
        finally:
            with _weather_lock:
                _weather_state['running'] = False

    threading.Thread(target=run, name='weather-refresh', daemon=True).start()


def weather(settings, now):
    cache = load_dict('weather')
    location = weather_location(settings)
    cached_place = cache.get('location') if isinstance(cache.get('location'), dict) else {}
    try:
        fetched = datetime.fromisoformat(str(cache.get('timestamp') or ''))
    except ValueError:
        fetched = None
    if location:
        stale = not fetched or now - fetched > WEATHER_MAX_AGE or not isinstance(cache.get('hourly'), dict) or cached_place.get('city') != location['city']
        if stale:
            refresh_weather_soon(location)
    place = location['city'] if location else str(cached_place.get('city') or '')
    if location and cached_place.get('city') != location['city']:
        return {'place': place, 'high': None, 'low': None, 'wind': None, 'hours': []}
    day = now.date().isoformat()
    tomorrow = (now.date() + timedelta(days=1)).isoformat()

    def rounded(value):
        return round(value) if isinstance(value, (int, float)) else None

    hourly = cache.get('hourly') if isinstance(cache.get('hourly'), dict) else {}
    times = hourly.get('time') if isinstance(hourly.get('time'), list) else []
    temps = hourly.get('temperature_2m') if isinstance(hourly.get('temperature_2m'), list) else []
    rains = hourly.get('precipitation_probability') if isinstance(hourly.get('precipitation_probability'), list) else []
    hours, morning = [], None
    for index, stamp in enumerate(times):
        stamp = str(stamp)
        temp = rounded(temps[index]) if index < len(temps) else None
        if len(stamp) < 13 or temp is None or not stamp[11:13].isdigit():
            continue
        hour = int(stamp[11:13])
        rain = (rounded(rains[index]) if index < len(rains) else None) or 0
        if stamp.startswith(day):
            hours.append({'h': hour, 'temp': temp, 'rain': rain})
        elif stamp.startswith(tomorrow) and hour == 7:
            morning = {'temp': temp, 'rain': rain}
    daily = cache.get('daily') if isinstance(cache.get('daily'), dict) else {}
    dates = daily.get('time') if isinstance(daily.get('time'), list) else []

    def today_value(key):
        values = daily.get(key)
        if day not in dates or not isinstance(values, list):
            return None
        index = dates.index(day)
        return rounded(values[index]) if index < len(values) else None

    current = cache.get('current') if isinstance(cache.get('current'), dict) else {}
    fresh = str(current.get('time') or '').startswith(day)
    view = {
        'place': place,
        'high': today_value('temperature_2m_max'),
        'low': today_value('temperature_2m_min'),
        'wind': rounded(current.get('wind_speed_10m')) if fresh else None,
        'hours': hours,
    }
    if morning:
        view['tomorrowMorning'] = morning
    return view


def iserv_account():
    credentials = load_dict('iserv')
    username = str(credentials.get('username') or '')
    return {'connected': bool(username), 'name': username, 'school': str(credentials.get('iserv_url') or '').replace('https://', '').rstrip('/'), 'features': ['Aufgaben', 'Vertretungsplan', 'E-Mail'] if username else []}


def build(active, store, now):
    today = now.date()
    settings = db.get_timetable_settings() or {}
    school = school_setup(settings)
    plan, pool = tasks(school['subjects'], today)
    iserv = iserv_account()
    data = {
        'user': {},
        'blocks': school['blocks'],
        'subjects': school['subjects'],
        'courses': school['courses'],
        'timetable': school['timetable'],
        'abReference': school['abReference'],
        'changes': [],
        'tasks': plan,
        'taskPool': pool,
        'deadlines': deadlines(school, today),
        'events': events(today),
        'holidays': holidays(today),
        'transit': {'line': '', 'mode': '', 'from': '', 'to': '', 'walkMinutes': 0, 'departures': [], 'delays': {}},
        'weather': weather(settings, now),
        'status': {'iserv': iserv['connected'], 'lastSync': f'{now.hour}:{now.minute:02d}'},
        'mailUnread': 0,
    }
    if not school['abWeeks']:
        store.setdefault('app-ab-weeks', False)
    if active in PAGE_BUILDERS:
        data['page'] = PAGE_BUILDERS[active](data, school, settings, today, iserv)
    return data


def page_assistant(data, school, settings, today, iserv):
    from . import local_ai
    return {'install': local_ai.status()}


def page_calendar(data, school, settings, today, iserv):
    code = settings.get('bundesland') or ''
    return {'region': dict(STATES).get(code, ''), 'events': [], 'holidays': data['holidays'], 'notes': {}}


def semester_for(today, level):
    if isinstance(level, int) and level >= 11:
        first = 'Q1' if level == 11 else 'Q3'
        second = 'Q2' if level == 11 else 'Q4'
        return first if today.month >= 8 or today.month == 1 else second
    half = 1 if today.month >= 8 or today.month == 1 else 2
    return f'{level or 10}/{half}'


def page_school(data, school, settings, today, iserv):
    semester = semester_for(today, settings.get('class_level'))
    grades = []
    history = {}
    for item in load_list('grades'):
        subject_key = str(item.get('subject_id') or '')
        points = item.get('points')
        when = iso_day(item.get('date')) or today.isoformat()
        if subject_key not in school['subjects'] or not isinstance(points, (int, float)):
            continue
        term = str(item.get('semester') or semester)
        entry = {
            'id': f"g-{item.get('id')}",
            'subject': subject_key,
            'points': int(round(points)),
            'type': item.get('type') if item.get('type') in ('klausur', 'test', 'muendlich', 'sonstiges') else 'sonstiges',
            'semester': term,
            'date': when,
            'title': str(item.get('description') or ''),
        }
        if term == semester:
            grades.append(entry)
        else:
            history.setdefault(subject_key, {}).setdefault(term, []).append(entry['points'])
    history = {key: {term: round(sum(values) / len(values)) for term, values in terms.items()} for key, terms in history.items()}
    return {'courses': school['courses'], 'history': history, 'grades': grades, 'exams': [], 'changes': [], 'seminar': None, 'semester': semester}


def place_view(name, value):
    if not isinstance(value, dict):
        return None
    lat, lon = value.get('latitude'), value.get('longitude')
    if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
        return None
    stop = str(value.get('id') or '')
    usable = stop if stop.startswith('de-') else None
    return {'id': usable or f'{lat},{lon}', 'name': name, 'detail': str(value.get('name') or value.get('address') or ''), 'stop': usable, 'lat': lat, 'lon': lon}


def known_places():
    try:
        from .vbb_service import get_vbb_service
        places = get_vbb_service().get_known_locations().get('locations')
        return places if isinstance(places, dict) else {}
    except Exception:
        return load_dict('places')


def page_transit(data, school, settings, today, iserv):
    known = known_places()
    places = {}
    home = place_view('Zuhause', known.get('home'))
    school_place = place_view('Schule', known.get('school'))
    if home:
        places['home'] = home
    if school_place:
        places['school'] = school_place
    return {'places': places, 'attribution': 'Transitous, DELFI e.V. und Verkehrsverbünde'}


def page_email(data, school, settings, today, iserv):
    return {'messages': [], 'contacts': []}


def page_settings(data, school, settings, today, iserv):
    google = load_dict('google')
    city = (weather_location(settings) or {}).get('city') or ''
    known = known_places()
    return {
        'school': {
            'name': iserv['school'],
            'town': city or '',
            'state': settings.get('bundesland') or '',
            'grade': settings.get('class_level') or 10,
            'semester': semester_for(today, settings.get('class_level')),
            'birthday': iso_day(settings.get('birthday')) or '',
        },
        'states': [{'code': code, 'name': name} for code, name in STATES],
        'courses': school['courses'],
        'accounts': {
            'iserv': iserv,
            'google': {'connected': bool(google), 'calendars': []},
        },
        'notifications': copy.deepcopy(NOTIFY_DEFAULTS),
        'places': {
            'weather': city or '',
            'home': str((known.get('home') or {}).get('name') or '') if isinstance(known.get('home'), dict) else '',
            'school': str((known.get('school') or {}).get('name') or '') if isinstance(known.get('school'), dict) else '',
        },
        'about': {'version': '', 'license': 'AGPL-3.0', 'website': brand.WEBSITE, 'source': brand.REPOSITORY},
    }


PAGE_BUILDERS = {
    'calendar': page_calendar,
    'school': page_school,
    'vbb': page_transit,
    'email': page_email,
    'settings': page_settings,
    'assistant': page_assistant,
}


def _update_settings(columns):
    conn = db.get_connection()
    cursor = conn.cursor()
    db._execute(cursor, 'SELECT id FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    row = db._fetchone_dict(cursor)
    names = list(columns)
    if row:
        assignments = ', '.join(f'{name} = ?' for name in names)
        db._execute(cursor, f'UPDATE hub_timetable_settings SET {assignments}, updated_at = CURRENT_TIMESTAMP WHERE id = ?', [*columns.values(), row['id']])
    else:
        db._execute(cursor, f"INSERT INTO hub_timetable_settings ({', '.join(names)}) VALUES ({', '.join('?' for _ in names)})", list(columns.values()))
    conn.commit()
    conn.close()


def mirror_store(key, value):
    if key == 'app-ab-weeks':
        _update_settings({'has_ab_weeks': 0 if value is False else 1})
    elif key == 'app-theme-choice' and value in ('light', 'dark'):
        db.save_user_theme(theme=value)
    elif key == 'app-settings' and isinstance(value, dict):
        school = value.get('school') if isinstance(value.get('school'), dict) else {}
        columns = {}
        grade = school.get('grade')
        if isinstance(grade, int) and 5 <= grade <= 13:
            columns['class_level'] = grade
            columns['grade_system'] = 'points' if grade >= 11 else 'marks'
        if 'birthday' in school:
            columns['birthday'] = iso_day(school.get('birthday')) or None
        if columns:
            _update_settings(columns)
