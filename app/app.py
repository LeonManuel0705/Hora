# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

from flask import Flask, request, jsonify, render_template, redirect, url_for, session, g
from flask_cors import CORS
from flask_socketio import SocketIO
from werkzeug.exceptions import HTTPException
from functools import wraps
from urllib.parse import urlencode, urlsplit
import os
import sys
import uuid
import logging
from datetime import datetime, timedelta
from pathlib import Path
import json
import re
import time
import secrets
import hmac
import hashlib
import threading
import html as html_mod
import requests

from . import database as db

try:
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env'))
except ImportError:
    pass

from .crypto_utils import _get_secret_key, encrypt_file, decrypt_file
from . import brand

app = Flask(__name__, static_folder='static')

_raw_key = _get_secret_key()
app.secret_key = hmac.new(_raw_key.encode() if isinstance(_raw_key, str) else _raw_key, b'flask-session', 'sha256').hexdigest()
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
app.config['SESSION_COOKIE_SECURE'] = os.environ.get('HUB_HTTPS') == '1'
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=30)
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024
app.config['TEMPLATES_AUTO_RELOAD'] = True
app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 0

ALLOWED_ORIGINS = os.environ.get(
    'CORS_ORIGINS', 'http://127.0.0.1:5050,http://localhost:5050'
).split(',')
CORS(app, origins=ALLOWED_ORIGINS)
socketio = SocketIO(app, cors_allowed_origins=ALLOWED_ORIGINS, async_mode='threading')

try:
    from flask_limiter import Limiter
    from flask_limiter.util import get_remote_address
    limiter = Limiter(get_remote_address, app=app, default_limits=["200 per minute"],
                      storage_uri="memory://")
except ImportError:
    pass

def _read_build_info():
    try:
        build_info_path = Path(__file__).parent.parent / 'flutter_app' / 'lib' / 'build_info.dart'
        content = build_info_path.read_text()
        version_name = re.search(r"versionName = '(.+?)'", content)
        build_number = re.search(r"buildNumber = (\d+)", content)
        if version_name and build_number:
            return f"{version_name.group(1)} (Build {build_number.group(1)})"
    except Exception:
        pass
    return brand.NAME

_cached_version = None
_cached_version_mtime = 0

def _get_app_version():
    global _cached_version, _cached_version_mtime
    build_info_path = Path(__file__).parent.parent / 'flutter_app' / 'lib' / 'build_info.dart'
    try:
        mtime = build_info_path.stat().st_mtime
        if mtime != _cached_version_mtime:
            _cached_version = _read_build_info()
            _cached_version_mtime = mtime
    except OSError:
        pass
    return _cached_version or _read_build_info()

@app.context_processor
def inject_globals():
    theme = db.get_user_theme()
    css_path = os.path.join(app.static_folder, 'css', 'hub.css')
    try:
        cache_bust = int(os.path.getmtime(css_path))
    except OSError:
        cache_bust = int(time.time())
    tour_state = db.get_tour_state()
    tour_auto = tour_state is None and not db.has_hub_tasks()
    return {'app_version': _get_app_version(), 'user_theme': theme, 'cache_bust': cache_bust, 'brand_name': brand.NAME, 'brand_previous': ','.join(brand.PREVIOUS_NAMES), 'brand_repository': brand.REPOSITORY, 'tour_auto': tour_auto}

from .paths import DATA_DIR, env
API_TOKEN_FILE = DATA_DIR / '.api_token'

def _get_api_token() -> str:
    try:
        data = decrypt_file(API_TOKEN_FILE)
        if data and data.get('token'):
            return data['token']
    except Exception:
        pass
    token = secrets.token_hex(32)
    encrypt_file({'token': token}, API_TOKEN_FILE)
    logging.info("New API token generated. Retrieve with: python -c \"from app.crypto_utils import decrypt_file; from pathlib import Path; print(decrypt_file(Path('data/.api_token'))['token'])\"")
    return token

API_TOKEN = _get_api_token()


def _same_secret(supplied: str, expected: str) -> bool:
    return hmac.compare_digest(supplied.encode(), expected.encode())


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get('Authorization', '')
        if _same_secret(auth, f'Bearer {API_TOKEN}'):
            return f(*args, **kwargs)
        return jsonify({'error': 'Unauthorized'}), 401
    return decorated

@app.after_request
def set_security_headers(response):
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    nonce = getattr(g, 'csp_nonce', None)
    script_src = f"'self' 'nonce-{nonce}'" if nonce and request.blueprint == 'ui' else "'self' 'unsafe-inline'"
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        f"script-src {script_src}; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' https://fonts.gstatic.com; "
        "img-src 'self' data: https:; "
        "connect-src 'self'; "
        "object-src 'none'; "
        "base-uri 'none'; "
        "form-action 'self'; "
        "frame-ancestors 'none'"
    )
    if request.is_secure:
        response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    if request.path.startswith('/static/'):
        response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
        response.headers['Pragma'] = 'no-cache'
    return response

def _bounded_str(value, max_len=500):
    """Truncate string query parameters to prevent DoS via oversized inputs."""
    return value[:max_len] if value else value

@app.errorhandler(Exception)
def handle_exception(e):
    if isinstance(e, HTTPException):
        return e
    logging.exception("Unhandled exception")
    return jsonify({'error': 'Internal server error'}), 500

@app.before_request
def generate_csp_nonce():
    g.csp_nonce = secrets.token_hex(16)

CANONICAL_LOOPBACK = '127.0.0.1'
LOOPBACK_ALIASES = {'localhost', '::1', '[::1]'}


@app.before_request
def canonicalise_loopback_host():
    if app.config.get('TESTING'):
        return
    if request.method not in SAFE_METHODS:
        return
    host = request.host
    if host.startswith('['):
        name, sep, rest = host.partition(']')
        if not sep:
            return
        name = name[1:]
        port_part = rest[1:] if rest.startswith(':') else rest
    elif ':' in host:
        name, _, port_part = host.rpartition(':')
    else:
        name, port_part = host, ''
    if name.lower() not in LOOPBACK_ALIASES:
        return
    if port_part and not port_part.isdigit():
        return
    port = f':{port_part}' if port_part else ''
    query = request.query_string.decode('latin-1')
    target = f'{request.scheme}://{CANONICAL_LOOPBACK}{port}{request.path}'
    if query:
        target = f'{target}?{query}'
    return redirect(target)

AUTH_EXEMPT_PATHS = {'/api/ping', '/api/email/google/oauth-callback', '/api/desktop-handshake', '/api/desktop-login-code'}

SAFE_METHODS = {'GET', 'HEAD', 'OPTIONS'}

DESKTOP_TOKEN = os.environ.get('HUB_DESKTOP_TOKEN') or None

_SECRET_IN_QUERY = re.compile(r'((?:token|code)=)[^&\s"\']+')


class _RedactTokenFilter(logging.Filter):
    def filter(self, record):
        if isinstance(record.msg, str):
            record.msg = _SECRET_IN_QUERY.sub(r'\1<redacted>', record.msg)
        if isinstance(record.args, tuple):
            record.args = tuple(
                _SECRET_IN_QUERY.sub(r'\1<redacted>', a) if isinstance(a, str) else a
                for a in record.args
            )
        return True


logging.getLogger('werkzeug').addFilter(_RedactTokenFilter())

CROSS_SITE_EXEMPT_PATHS = {'/api/email/google/oauth-callback'}


def _origin_host(origin):
    try:
        return urlsplit(origin).netloc
    except ValueError:
        return None


@app.before_request
def refuse_cross_site_api_requests():
    if not request.path.startswith('/api/') or request.path in CROSS_SITE_EXEMPT_PATHS:
        return
    origin = request.headers.get('Origin')
    if origin in ALLOWED_ORIGINS:
        return
    if request.headers.get('Sec-Fetch-Site') in ('cross-site', 'same-site'):
        return jsonify({'error': 'Cross-site request refused'}), 403
    if origin and request.method not in SAFE_METHODS and _origin_host(origin) != request.host:
        return jsonify({'error': 'Cross-site request refused'}), 403


def _token_grants_web_session(supplied: str) -> bool:
    if not supplied:
        return False
    if _same_secret(supplied, API_TOKEN):
        return True
    if DESKTOP_TOKEN and _same_secret(supplied, DESKTOP_TOKEN):
        return True
    return False


HEX64 = re.compile(r'[0-9a-f]{64}')
HANDSHAKE_CONTEXT = 'hub-desktop-handshake:'
LOGIN_CODE_TTL = 60
LOGIN_CODE_LIMIT = 5
LOGIN_PARAMS = ('token', 'login_code')
_login_codes = {}
_login_codes_lock = threading.Lock()


def _no_store(response):
    response.headers['Cache-Control'] = 'no-store'
    return response


@app.route('/api/desktop-handshake')
def desktop_handshake():
    if not DESKTOP_TOKEN:
        return jsonify({'error': 'Not found'}), 404
    nonce = request.args.get('nonce', '')
    if not HEX64.fullmatch(nonce):
        return jsonify({'error': 'Invalid nonce'}), 400
    mac = hmac.new(DESKTOP_TOKEN.encode(), (HANDSHAKE_CONTEXT + nonce).encode(), hashlib.sha256).hexdigest()
    return _no_store(jsonify({'mac': mac}))


@app.route('/api/desktop-login-code', methods=['POST'])
def desktop_login_code():
    if not DESKTOP_TOKEN:
        return jsonify({'error': 'Not found'}), 404
    supplied = request.headers.get('X-Hub-Token', '')
    if not _same_secret(supplied, DESKTOP_TOKEN):
        return jsonify({'error': 'Unauthorized'}), 401
    code = secrets.token_hex(32)
    now = time.monotonic()
    with _login_codes_lock:
        for known, expires in list(_login_codes.items()):
            if expires <= now:
                del _login_codes[known]
        while len(_login_codes) >= LOGIN_CODE_LIMIT:
            del _login_codes[next(iter(_login_codes))]
        _login_codes[code] = now + LOGIN_CODE_TTL
    return _no_store(jsonify({'code': code}))


def _redeem_login_code(code):
    if not HEX64.fullmatch(code):
        return False
    with _login_codes_lock:
        for known in list(_login_codes):
            if hmac.compare_digest(known, code):
                return _login_codes.pop(known) > time.monotonic()
    return False


@app.before_request
def check_api_auth():
    if not request.path.startswith('/api/'):
        if not request.path.startswith('/hub'):
            return
        supplied = request.args.get('token', '') or request.headers.get('X-Hub-Token', '')
        redeemed = _redeem_login_code(request.args.get('login_code', ''))
        if redeemed or (supplied and _token_grants_web_session(supplied)):
            session['web_auth'] = True
            session.permanent = True
        if session.get('web_auth'):
            if not any(param in request.args for param in LOGIN_PARAMS):
                return
            rest = {k: v for k, v in request.args.items(multi=False) if k not in LOGIN_PARAMS}
            target = request.path + (f'?{urlencode(rest)}' if rest else '')
            return redirect(target)
        if request.method not in SAFE_METHODS:
            return jsonify({'error': 'Unauthorized'}), 401
        return render_template('unauthorized.html', brand_name=brand.NAME), 401
    if request.path in AUTH_EXEMPT_PATHS:
        return
    # NOTE: No blanket loopback bypass. In desktop/Electron mode the web UI is
    # authenticated by the signed `web_auth` session cookie, which a /hub visit
    # establishes only against the token, and the Flutter client uses the Bearer
    # token. A loopback carve-out would let ANY local process — or a browser page
    # issuing CSRF requests to http://localhost:5050/api/... — act as
    # authenticated.
    auth = request.headers.get('Authorization', '')
    if _same_secret(auth, f'Bearer {API_TOKEN}'):
        return
    if session.get('web_auth'):
        return
    return jsonify({'error': 'Unauthorized'}), 401


@socketio.on('connect')
def _socketio_authorize(auth=None):
    if session.get('web_auth'):
        return None
    supplied = ''
    if isinstance(auth, dict):
        supplied = auth.get('token') or ''
    if _token_grants_web_session(supplied):
        return None
    return False

@app.route('/')
def landing():

    return redirect(url_for('hub_home'))

@app.route('/welcome')
def welcome_page():

    return render_template('landing.html')

@app.route('/apps')
def apps_selection():

    return render_template('apps.html')

@app.route('/hub/logout', methods=['POST'])
def hub_logout():
    session.pop('web_auth', None)
    session.clear()
    response = jsonify({'success': True})
    response.headers['Clear-Site-Data'] = '"cache", "storage"'
    return response

@app.route('/hub/klassisch')
def hub_home():
    return render_template('hub/home.html', active_tab='dashboard')

@app.route('/hub/klassisch/tasks')
def hub_tasks():
    return render_template('hub/tasks.html', active_tab='tasks')

@app.route('/hub/klassisch/calendar')
def hub_calendar():
    return render_template('hub/calendar.html', active_tab='calendar')

@app.route('/hub/klassisch/school')
def hub_school():
    return render_template('hub/school.html', active_tab='school')

@app.route('/hub/training')
def hub_training():
    return render_template('hub/training.html', active_tab='training')

@app.route('/hub/review')
def hub_review():
    return render_template('hub/review.html', active_tab='review')

@app.route('/hub/assistant')
def hub_assistant():
    return render_template('hub/assistant.html', active_tab='assistant')

@app.route('/hub/klassisch/settings')
def hub_settings():
    return render_template('hub/settings.html', active_tab='settings')

@app.route('/hub/terms')
def hub_terms():
    return render_template('hub/terms.html', active_tab='settings')

@app.route('/hub/privacy')
def hub_privacy():
    return render_template('hub/privacy.html', active_tab='settings')

@app.route('/hub/klassisch/email')
def hub_email():
    return render_template('hub/email.html', active_tab='email')

@app.route('/hub/pomodoro')
def hub_pomodoro():
    return render_template('hub/pomodoro.html', active_tab='pomodoro')

@app.route('/hub/bookmarks')
def hub_bookmarks():
    return render_template('hub/bookmarks.html', active_tab='bookmarks')

@app.route('/hub/klassisch/vbb')
def hub_vbb():
    return render_template('hub/vbb.html', active_tab='vbb')


from .ui_pages import bp as ui_blueprint
app.register_blueprint(ui_blueprint)


@app.route('/api/ping', methods=['HEAD', 'GET'])
def ping():

    return '', 204

@app.route('/api/iserv/ping', methods=['HEAD', 'GET'])
def iserv_ping():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    status = service.get_status()
    if status.get('connected') or status.get('has_credentials'):
        return '', 204
    return '', 503

@app.route('/api/hub/tasks', methods=['GET'])
def get_hub_tasks_api():

    filter_type = _bounded_str(request.args.get('filter', 'all'))
    user_id = request.args.get('user_id')
    tasks = db.get_hub_tasks(filter_type, user_id=user_id)
    return jsonify({'success': True, 'tasks': tasks})

@app.route('/api/hub/tasks', methods=['POST'])
def create_hub_task_api():

    data = request.get_json()
    if not data or not data.get('title'):
        return jsonify({'success': False, 'error': 'Title is required'}), 400

    task_id = db.create_hub_task(
        title=data.get('title'),
        description=data.get('description'),
        due_date=data.get('due_date'),
        due_time=data.get('due_time'),
        priority=data.get('priority', 'medium'),
        category=data.get('category'),
        user_id=data.get('user_id'),
        repeat_type=data.get('repeat_type', 'none'),
        repeat_days=data.get('repeat_days'),
        repeat_end_date=data.get('repeat_end_date')
    )
    task = db.get_hub_task(task_id)
    return jsonify({'success': True, 'task': task})

@app.route('/api/hub/tasks/<int:task_id>', methods=['GET'])
def get_hub_task_api(task_id):

    task = db.get_hub_task(task_id)
    if not task:
        return jsonify({'success': False, 'error': 'Task not found'}), 404
    return jsonify({'success': True, 'task': task})

@app.route('/api/hub/tasks/<int:task_id>', methods=['PUT'])
def update_hub_task_api(task_id):

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    success = db.update_hub_task(
        task_id,
        title=data.get('title'),
        description=data.get('description'),
        due_date=data.get('due_date'),
        due_time=data.get('due_time'),
        priority=data.get('priority'),
        category=data.get('category'),
        repeat_type=data.get('repeat_type'),
        repeat_days=data.get('repeat_days'),
        repeat_end_date=data.get('repeat_end_date')
    )

    if success:
        task = db.get_hub_task(task_id)
        return jsonify({'success': True, 'task': task})
    return jsonify({'success': False, 'error': 'Task not found or no changes made'}), 404

@app.route('/api/hub/tasks/<int:task_id>', methods=['DELETE'])
def delete_hub_task_api(task_id):

    success = db.delete_hub_task(task_id)
    if success:
        return jsonify({'success': True})
    return jsonify({'success': False, 'error': 'Task not found'}), 404

@app.route('/api/hub/tasks/<int:task_id>/toggle', methods=['POST'])
def toggle_hub_task_api(task_id):

    stop_recurrence = request.args.get('stop_recurrence') == '1'
    result = db.toggle_hub_task(task_id, stop_recurrence=stop_recurrence)
    if result.get('success'):
        task = db.get_hub_task(task_id)
        response = {'success': True, 'task': task}

        if result.get('next_task_id'):
            next_task = db.get_hub_task(result['next_task_id'])
            response['next_task'] = next_task
        return jsonify(response)
    return jsonify({'success': False, 'error': 'Task not found'}), 404

@app.route('/api/hub/tasks/<int:task_id>/delete-all', methods=['DELETE'])
def delete_hub_task_all_api(task_id):

    affected = db.delete_hub_task_all_occurrences(task_id)
    if affected > 0:
        return jsonify({'success': True, 'deleted_count': affected})
    return jsonify({'success': False, 'error': 'Task not found'}), 404

@app.route('/api/hub/tasks/<int:task_id>/skip', methods=['POST'])
def skip_hub_task_api(task_id):

    result = db.skip_hub_task_occurrence(task_id)
    if result:
        return jsonify({
            'success': True,
            'deleted': result.get('deleted'),
            'next_task': result.get('next_task')
        })
    return jsonify({'success': False, 'error': 'Task not found'}), 404

@app.route('/api/hub/reviews', methods=['GET'])
def get_reviews():

    review_type = _bounded_str(request.args.get('type'))
    reviews = db.get_hub_reviews(review_type=review_type)
    return jsonify({'reviews': reviews})

@app.route('/api/hub/reviews', methods=['POST'])
def create_review():

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    review_type = data.get('type', 'daily')
    date = data.get('date')
    energy = data.get('energy')

    review_data = {k: v for k, v in data.items() if k not in ['type', 'date', 'energy', 'id']}
    data_json = json.dumps(review_data) if review_data else None

    review_id = db.create_hub_review(review_type, date, data_json, energy)
    review = db.get_hub_review(review_id)

    return jsonify({'success': True, 'review': review})

@app.route('/api/hub/reviews/<int:review_id>', methods=['GET'])
def get_review(review_id):

    review = db.get_hub_review(review_id)
    if not review:
        return jsonify({'success': False, 'error': 'Review not found'}), 404
    return jsonify({'success': True, 'review': review})

@app.route('/api/hub/reviews/<int:review_id>', methods=['PUT'])
def update_review(review_id):

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    review = db.get_hub_review(review_id)
    if not review:
        return jsonify({'success': False, 'error': 'Review not found'}), 404

    energy = data.get('energy')
    review_data = {k: v for k, v in data.items() if k not in ['type', 'date', 'energy', 'id']}
    data_json = json.dumps(review_data) if review_data else None

    db.update_hub_review(review_id, data=data_json, energy=energy)
    updated_review = db.get_hub_review(review_id)

    return jsonify({'success': True, 'review': updated_review})

@app.route('/api/hub/reviews/<int:review_id>', methods=['DELETE'])
def delete_review(review_id):

    db.delete_hub_review(review_id)
    return jsonify({'success': True})


@app.route('/api/hub/bookmarks', methods=['GET'])
def get_bookmarks():
    category = request.args.get('category')
    bookmarks = db.get_hub_bookmarks(category=category)
    return jsonify({'bookmarks': bookmarks})

@app.route('/api/hub/bookmarks', methods=['POST'])
def create_bookmark():
    data = request.get_json()
    if not data or not data.get('title') or not data.get('url'):
        return jsonify({'success': False, 'error': 'Title and URL required'}), 400
    bookmark_id = db.create_hub_bookmark(
        title=data['title'],
        url=data['url'],
        category=data.get('category', 'Other'),
        favicon=data.get('favicon')
    )
    bookmark = db.get_hub_bookmark(bookmark_id)
    return jsonify({'success': True, 'bookmark': bookmark})

@app.route('/api/hub/bookmarks/<int:bookmark_id>', methods=['PUT'])
def update_bookmark(bookmark_id):
    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400
    bookmark = db.get_hub_bookmark(bookmark_id)
    if not bookmark:
        return jsonify({'success': False, 'error': 'Bookmark not found'}), 404
    db.update_hub_bookmark(bookmark_id, **{k: data[k] for k in ('title', 'url', 'category', 'favicon') if k in data})
    updated = db.get_hub_bookmark(bookmark_id)
    return jsonify({'success': True, 'bookmark': updated})

@app.route('/api/hub/bookmarks/<int:bookmark_id>', methods=['DELETE'])
def delete_bookmark(bookmark_id):
    db.delete_hub_bookmark(bookmark_id)
    return jsonify({'success': True})

SCHOOL_SUBJECTS_FILE = DATA_DIR / 'school_subjects.json'
SCHOOL_HOMEWORK_FILE = DATA_DIR / 'school_homework.json'
SCHOOL_TESTS_FILE = DATA_DIR / 'school_tests.json'
SCHOOL_EXAMS_FILE = DATA_DIR / 'school_exams.json'
SCHOOL_GRADES_FILE = DATA_DIR / 'school_grades.json'
SCHOOL_CALENDAR_FILE = DATA_DIR / 'school_calendar.json'
ASSISTANT_CHAT_FILE = DATA_DIR / 'assistant_chat_history.json'
ASSISTANT_CHAT_CAP = 200
ASSISTANT_LLM_CONTEXT_TURNS = 12


def load_assistant_history():
    try:
        data = decrypt_file(ASSISTANT_CHAT_FILE)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def save_assistant_history(history):
    if not isinstance(history, list):
        history = []
    if len(history) > ASSISTANT_CHAT_CAP:
        history = history[-ASSISTANT_CHAT_CAP:]
    encrypt_file(history, ASSISTANT_CHAT_FILE)


def append_assistant_history(role, content):
    if role not in ('user', 'assistant') or not isinstance(content, str):
        return
    content = content.strip()
    if not content:
        return
    history = load_assistant_history()
    history.append({'role': role, 'content': content[:10000], 'ts': int(time.time())})
    save_assistant_history(history)

def load_school_subjects():
    try:
        return decrypt_file(SCHOOL_SUBJECTS_FILE) or []
    except Exception:
        return []

def save_school_subjects(subjects):
    encrypt_file(subjects, SCHOOL_SUBJECTS_FILE)

def load_school_homework():
    try:
        return decrypt_file(SCHOOL_HOMEWORK_FILE) or []
    except Exception:
        return []

def save_school_homework(homework):
    encrypt_file(homework, SCHOOL_HOMEWORK_FILE)

def load_school_tests():
    try:
        return decrypt_file(SCHOOL_TESTS_FILE) or []
    except Exception:
        return []

def save_school_tests(tests):
    encrypt_file(tests, SCHOOL_TESTS_FILE)

def load_school_exams():
    try:
        return decrypt_file(SCHOOL_EXAMS_FILE) or []
    except Exception:
        return []

def save_school_exams(exams):
    encrypt_file(exams, SCHOOL_EXAMS_FILE)

def load_school_grades():
    try:
        return decrypt_file(SCHOOL_GRADES_FILE) or []
    except Exception:
        return []

def save_school_grades(grades):
    encrypt_file(grades, SCHOOL_GRADES_FILE)

def load_school_calendar():
    try:
        return decrypt_file(SCHOOL_CALENDAR_FILE) or []
    except Exception:
        return []

def save_school_calendar(events):
    encrypt_file(events, SCHOOL_CALENDAR_FILE)

@app.route('/api/hub/school/subjects', methods=['GET'])
def get_school_subjects():

    subjects = load_school_subjects()
    return jsonify({'subjects': subjects})

@app.route('/api/hub/school/subjects', methods=['POST'])
def create_school_subject():

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    subjects = load_school_subjects()

    subject_id = str(uuid.uuid4())[:8]

    subject = {
        'id': subject_id,
        'name': data.get('name'),
        'teacher': data.get('teacher', ''),
        'room': data.get('room', ''),
        'color': data.get('color', '#667eea'),
        'grade': data.get('grade'),
        'course_type': data.get('course_type', 'GK'),
        'created_at': datetime.now().isoformat()
    }

    subjects.append(subject)
    save_school_subjects(subjects)

    return jsonify({'success': True, 'subject': subject})

@app.route('/api/hub/school/subjects/<subject_id>', methods=['PUT'])
def update_school_subject(subject_id):

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    subjects = load_school_subjects()
    subject_index = next((i for i, s in enumerate(subjects) if s['id'] == subject_id), None)

    if subject_index is None:
        return jsonify({'success': False, 'error': 'Subject not found'}), 404

    subjects[subject_index].update({
        'name': data.get('name', subjects[subject_index].get('name')),
        'teacher': data.get('teacher', subjects[subject_index].get('teacher')),
        'room': data.get('room', subjects[subject_index].get('room')),
        'color': data.get('color', subjects[subject_index].get('color')),
        'grade': data.get('grade', subjects[subject_index].get('grade')),
        'course_type': data.get('course_type', subjects[subject_index].get('course_type', 'GK')),
        'updated_at': datetime.now().isoformat()
    })

    save_school_subjects(subjects)
    return jsonify({'success': True, 'subject': subjects[subject_index]})

@app.route('/api/hub/school/subjects/<subject_id>', methods=['DELETE'])
def delete_school_subject(subject_id):

    subjects = load_school_subjects()
    subjects = [s for s in subjects if s['id'] != subject_id]
    save_school_subjects(subjects)
    return jsonify({'success': True})

@app.route('/api/hub/school/homework', methods=['GET'])
def get_school_homework():

    homework = load_school_homework()
    today = datetime.now().date()
    cleaned = [h for h in homework if not h.get('due_date') or
               (datetime.strptime(h['due_date'], '%Y-%m-%d').date() - today).days >= -1]
    if len(cleaned) < len(homework):
        save_school_homework(cleaned)
    return jsonify({'homework': cleaned})

@app.route('/api/hub/school/homework', methods=['POST'])
def create_school_homework():

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    homework_list = load_school_homework()

    homework_id = str(uuid.uuid4())[:8]

    homework = {
        'id': homework_id,
        'subject_id': data.get('subject_id'),
        'title': data.get('title'),
        'due_date': data.get('due_date'),
        'notes': data.get('notes', ''),
        'completed': False,
        'created_at': datetime.now().isoformat()
    }

    homework_list.append(homework)
    save_school_homework(homework_list)

    return jsonify({'success': True, 'homework': homework})

@app.route('/api/hub/school/homework/<homework_id>', methods=['PUT'])
def update_school_homework(homework_id):

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    homework_list = load_school_homework()
    homework_index = next((i for i, h in enumerate(homework_list) if h['id'] == homework_id), None)

    if homework_index is None:
        return jsonify({'success': False, 'error': 'Homework not found'}), 404

    homework_list[homework_index].update({
        'subject_id': data.get('subject_id', homework_list[homework_index].get('subject_id')),
        'title': data.get('title', homework_list[homework_index].get('title')),
        'due_date': data.get('due_date', homework_list[homework_index].get('due_date')),
        'notes': data.get('notes', homework_list[homework_index].get('notes')),
        'completed': data.get('completed', homework_list[homework_index].get('completed')),
        'updated_at': datetime.now().isoformat()
    })

    save_school_homework(homework_list)
    return jsonify({'success': True, 'homework': homework_list[homework_index]})

@app.route('/api/hub/school/homework/<homework_id>', methods=['DELETE'])
def delete_school_homework(homework_id):

    homework_list = load_school_homework()
    homework_list = [h for h in homework_list if h['id'] != homework_id]
    save_school_homework(homework_list)
    return jsonify({'success': True})

@app.route('/api/hub/school/homework/<homework_id>/toggle', methods=['POST'])
def toggle_school_homework(homework_id):

    homework_list = load_school_homework()
    homework_index = next((i for i, h in enumerate(homework_list) if h['id'] == homework_id), None)

    if homework_index is None:
        return jsonify({'success': False, 'error': 'Homework not found'}), 404

    homework_list[homework_index]['completed'] = not homework_list[homework_index].get('completed', False)
    homework_list[homework_index]['updated_at'] = datetime.now().isoformat()

    save_school_homework(homework_list)
    return jsonify({'success': True, 'homework': homework_list[homework_index]})

@app.route('/api/hub/school/tests', methods=['GET'])
def get_school_tests():

    tests = load_school_tests()
    return jsonify({'tests': tests})

@app.route('/api/hub/school/tests', methods=['POST'])
def create_school_test():

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    tests = load_school_tests()

    test_id = str(uuid.uuid4())[:8]

    test = {
        'id': test_id,
        'subject_id': data.get('subject_id'),
        'title': data.get('title'),
        'date': data.get('date'),
        'time': data.get('time', ''),
        'topics': data.get('topics', ''),
        'created_at': datetime.now().isoformat()
    }

    tests.append(test)
    save_school_tests(tests)

    return jsonify({'success': True, 'test': test})

@app.route('/api/hub/school/tests/<test_id>', methods=['PUT'])
def update_school_test(test_id):

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    tests = load_school_tests()
    test_index = next((i for i, t in enumerate(tests) if t['id'] == test_id), None)

    if test_index is None:
        return jsonify({'success': False, 'error': 'Test not found'}), 404

    tests[test_index].update({
        'subject_id': data.get('subject_id', tests[test_index].get('subject_id')),
        'title': data.get('title', tests[test_index].get('title')),
        'date': data.get('date', tests[test_index].get('date')),
        'time': data.get('time', tests[test_index].get('time')),
        'topics': data.get('topics', tests[test_index].get('topics')),
        'updated_at': datetime.now().isoformat()
    })

    save_school_tests(tests)
    return jsonify({'success': True, 'test': tests[test_index]})

@app.route('/api/hub/school/tests/<test_id>', methods=['DELETE'])
def delete_school_test(test_id):

    tests = load_school_tests()
    tests = [t for t in tests if t['id'] != test_id]
    save_school_tests(tests)
    return jsonify({'success': True})

@app.route('/api/hub/school/exams', methods=['GET'])
def get_school_exams():

    exams = load_school_exams()
    return jsonify({'exams': exams})

@app.route('/api/hub/school/exams', methods=['POST'])
def create_school_exam():

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    exams = load_school_exams()

    exam_id = str(uuid.uuid4())[:8]

    exam = {
        'id': exam_id,
        'subject_id': data.get('subject_id'),
        'title': data.get('title'),
        'date': data.get('date'),
        'time': data.get('time', ''),
        'topics': data.get('topics', ''),
        'created_at': datetime.now().isoformat()
    }

    exams.append(exam)
    save_school_exams(exams)

    return jsonify({'success': True, 'exam': exam})

@app.route('/api/hub/school/exams/<exam_id>', methods=['PUT'])
def update_school_exam(exam_id):

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    exams = load_school_exams()
    exam_index = next((i for i, e in enumerate(exams) if e['id'] == exam_id), None)

    if exam_index is None:
        return jsonify({'success': False, 'error': 'Exam not found'}), 404

    exams[exam_index].update({
        'subject_id': data.get('subject_id', exams[exam_index].get('subject_id')),
        'title': data.get('title', exams[exam_index].get('title')),
        'date': data.get('date', exams[exam_index].get('date')),
        'time': data.get('time', exams[exam_index].get('time')),
        'topics': data.get('topics', exams[exam_index].get('topics')),
        'updated_at': datetime.now().isoformat()
    })

    save_school_exams(exams)
    return jsonify({'success': True, 'exam': exams[exam_index]})

@app.route('/api/hub/school/exams/<exam_id>', methods=['DELETE'])
def delete_school_exam(exam_id):

    exams = load_school_exams()
    exams = [e for e in exams if e['id'] != exam_id]
    save_school_exams(exams)
    return jsonify({'success': True})

@app.route('/api/hub/school/grade-system', methods=['GET'])
def get_grade_system():
    conn = db.get_connection()
    row = conn.execute('SELECT grade_system FROM hub_timetable_settings LIMIT 1').fetchone()
    system = row['grade_system'] if row and row['grade_system'] else 'points'
    return jsonify({'grade_system': system})

@app.route('/api/hub/school/grade-system', methods=['POST'])
def set_grade_system():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    system = data.get('grade_system', 'points')
    if system not in ('points', 'marks'):
        return jsonify({'error': 'Invalid grade system'}), 400
    conn = db.get_connection()
    existing = conn.execute('SELECT id FROM hub_timetable_settings LIMIT 1').fetchone()
    if existing:
        conn.execute('UPDATE hub_timetable_settings SET grade_system = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?', [system, existing['id']])
    else:
        conn.execute('INSERT INTO hub_timetable_settings (grade_system) VALUES (?)', [system])
    conn.commit()
    return jsonify({'grade_system': system})

@app.route('/api/hub/school/class-level', methods=['GET'])
def get_class_level():
    conn = db.get_connection()
    row = conn.execute('SELECT class_level FROM hub_timetable_settings LIMIT 1').fetchone()
    level = row['class_level'] if row and row['class_level'] else 10
    return jsonify({'class_level': level})

@app.route('/api/hub/school/class-level', methods=['POST'])
def set_class_level():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    level = data.get('class_level')
    if not isinstance(level, int) or level < 5 or level > 13:
        return jsonify({'error': 'Invalid class level (5-13)'}), 400
    system = 'marks' if level <= 10 else 'points'
    conn = db.get_connection()
    existing = conn.execute('SELECT id FROM hub_timetable_settings LIMIT 1').fetchone()
    if existing:
        conn.execute('UPDATE hub_timetable_settings SET class_level = ?, grade_system = ? WHERE id = ?',
                   [level, system, existing['id']])
    else:
        conn.execute('INSERT INTO hub_timetable_settings (class_level, grade_system) VALUES (?, ?)', [level, system])
    conn.commit()
    return jsonify({'class_level': level, 'grade_system': system})

@app.route('/api/hub/school/grades', methods=['GET'])
def get_school_grades():

    grades = load_school_grades()
    return jsonify({'grades': grades})

@app.route('/api/hub/school/grades', methods=['POST'])
def create_school_grade():

    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No data provided'}), 400

        grades = load_school_grades()

        grade = {
            'id': str(uuid.uuid4()),
            'subject_id': data.get('subject_id'),
            'points': data.get('points'),
            'type': data.get('type', 'test'),
            'date': data.get('date'),
            'description': data.get('description'),
            'semester': data.get('semester', 'Q1'),
            'grade_system': data.get('grade_system', 'points'),
            'value': data.get('value'),
            'created_at': datetime.now().isoformat()
        }

        grades.append(grade)
        save_school_grades(grades)
        return jsonify({'grade': grade})
    except Exception as e:
        logging.error(f"Failed to create grade: {e}")
        return jsonify({'error': 'Failed to create grade'}), 500

@app.route('/api/hub/school/grades/<grade_id>', methods=['PUT'])
def update_school_grade(grade_id):

    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No data provided'}), 400

        grades = load_school_grades()

        updated_grade = None
        for grade in grades:
            if grade['id'] == grade_id:
                grade['subject_id'] = data.get('subject_id', grade.get('subject_id'))
                grade['points'] = data.get('points', grade.get('points'))
                grade['type'] = data.get('type', grade.get('type'))
                grade['date'] = data.get('date', grade.get('date'))
                grade['description'] = data.get('description', grade.get('description'))
                grade['semester'] = data.get('semester', grade.get('semester', 'Q1'))
                grade['grade_system'] = data.get('grade_system', grade.get('grade_system', 'points'))
                grade['value'] = data.get('value', grade.get('value'))
                grade['updated_at'] = datetime.now().isoformat()
                updated_grade = grade
                break

        if updated_grade is None:
            return jsonify({'error': 'Grade not found'}), 404

        save_school_grades(grades)
        return jsonify({'grade': updated_grade})
    except Exception as e:
        logging.error(f"Failed to update grade: {e}")
        return jsonify({'error': 'Failed to update grade'}), 500

@app.route('/api/hub/school/grades/<grade_id>', methods=['DELETE'])
def delete_school_grade(grade_id):

    grades = load_school_grades()
    grades = [g for g in grades if g['id'] != grade_id]
    save_school_grades(grades)
    return jsonify({'success': True})

@app.route('/api/hub/school/calendar', methods=['GET'])
def get_school_calendar():

    events = load_school_calendar()
    return jsonify({'events': events})

@app.route('/api/hub/school/calendar', methods=['POST'])
def create_school_calendar_event():

    data = request.json
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    events = load_school_calendar()

    event = {
        'id': str(uuid.uuid4()),
        'title': data.get('title'),
        'date': data.get('date'),
        'time': data.get('time'),
        'end_date': data.get('end_date'),
        'end_time': data.get('end_time'),
        'category': data.get('category', 'personal'),
        'description': data.get('description'),
        'location': data.get('location'),
        'created_at': datetime.now().isoformat()
    }

    events.append(event)
    save_school_calendar(events)
    return jsonify({'success': True, 'event': event})

@app.route('/api/hub/school/calendar/<event_id>', methods=['PUT'])
def update_school_calendar_event(event_id):

    data = request.json
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    events = load_school_calendar()

    updated_event = None
    for event in events:
        if event['id'] == event_id:
            event['title'] = data.get('title', event.get('title'))
            event['date'] = data.get('date', event.get('date'))
            event['time'] = data.get('time', event.get('time'))
            event['end_date'] = data.get('end_date', event.get('end_date'))
            event['end_time'] = data.get('end_time', event.get('end_time'))
            event['category'] = data.get('category', event.get('category'))
            event['description'] = data.get('description', event.get('description'))
            event['location'] = data.get('location', event.get('location'))
            event['updated_at'] = datetime.now().isoformat()
            updated_event = event
            break

    if not updated_event:
        return jsonify({'error': 'Event not found'}), 404
    save_school_calendar(events)
    return jsonify({'event': updated_event})

@app.route('/api/hub/school/calendar/<event_id>', methods=['DELETE'])
def delete_school_calendar_event(event_id):

    events = load_school_calendar()
    events = [e for e in events if e['id'] != event_id]
    save_school_calendar(events)
    return jsonify({'success': True})

@app.route('/api/hub/school/timetable/settings', methods=['GET'])
def get_timetable_settings():

    user_id = request.args.get('user_id')
    settings = db.get_timetable_settings(user_id=user_id)
    if settings:
        return jsonify({'success': True, 'settings': settings})
    return jsonify({'success': True, 'settings': None, 'setup_required': True})

@app.route('/api/hub/school/timetable/settings', methods=['POST'])
def save_timetable_settings():

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    user_id = data.get('user_id')
    existing = db.get_timetable_settings(user_id=user_id)

    if existing:
        has_ab_weeks = data.get('has_ab_weeks', existing.get('has_ab_weeks', True))
        block_count = data.get('block_count', existing.get('block_count', 4))
        reference_date = data.get('reference_date', existing.get('reference_date'))
        setup_completed = data.get('setup_completed', existing.get('setup_completed', False))
    else:
        has_ab_weeks = data.get('has_ab_weeks', True)
        block_count = data.get('block_count', 4)
        reference_date = data.get('reference_date')
        setup_completed = data.get('setup_completed', False)

    settings_id = db.save_timetable_settings(
        has_ab_weeks=has_ab_weeks,
        block_count=block_count,
        reference_date=reference_date,
        setup_completed=setup_completed,
        user_id=user_id
    )
    return jsonify({'success': True, 'settings_id': settings_id})

@app.route('/api/hub/theme', methods=['GET'])
def get_theme():
    user_id = request.args.get('user_id')
    theme = db.get_user_theme(user_id=user_id)
    return jsonify({'success': True, 'theme': theme})

@app.route('/api/hub/theme', methods=['POST'])
def save_theme():
    data = request.get_json()
    if not data or 'theme' not in data:
        return jsonify({'success': False, 'error': 'No theme provided'}), 400
    theme = data['theme']
    if theme not in ('dark', 'light'):
        return jsonify({'success': False, 'error': 'Invalid theme'}), 400
    user_id = data.get('user_id')
    db.save_user_theme(theme=theme, user_id=user_id)
    return jsonify({'success': True})

@app.route('/hub/toggle-theme', methods=['POST'])
def toggle_theme():
    current = db.get_user_theme()
    new_theme = 'light' if current == 'dark' else 'dark'
    db.save_user_theme(theme=new_theme)
    referrer = request.referrer
    if referrer and referrer.startswith(request.host_url):
        return redirect(referrer)
    return redirect('/hub')

@app.route('/api/hub/theme-preferences', methods=['GET'])
def get_theme_preferences():
    prefs = db.get_theme_preferences()
    import json as _json
    schedule = None
    if prefs.get('theme_schedule_json'):
        try:
            schedule = _json.loads(prefs['theme_schedule_json'])
        except (ValueError, TypeError):
            pass
    return jsonify({
        'success': True,
        'theme': prefs['theme'],
        'theme_mode': prefs['theme_mode'],
        'schedule': schedule,
    })

@app.route('/api/hub/theme-preferences', methods=['POST'])
def save_theme_preferences():
    import json as _json
    data = request.get_json() or {}
    theme_mode = data.get('theme_mode', 'manual')
    if theme_mode not in ('manual', 'system', 'schedule'):
        return jsonify({'success': False, 'error': 'Invalid theme_mode'}), 400
    schedule = data.get('schedule')
    schedule_json = None
    if theme_mode == 'schedule' and schedule:
        light_time = schedule.get('light_time', '')
        dark_time = schedule.get('dark_time', '')
        if not light_time or not dark_time:
            return jsonify({'success': False, 'error': 'Schedule requires light_time and dark_time'}), 400
        schedule_json = _json.dumps({'light_time': light_time, 'dark_time': dark_time})
    db.save_theme_preferences(theme_mode=theme_mode, theme_schedule_json=schedule_json)
    return jsonify({'success': True})

@app.route('/api/hub/tour', methods=['GET'])
def get_tour_api():
    return jsonify({'success': True, 'state': db.get_tour_state()})

@app.route('/api/hub/tour', methods=['POST'])
def save_tour_api():
    data = request.get_json(silent=True) or {}
    state = data.get('state')
    if state not in db.TOUR_STATES:
        return jsonify({'success': False, 'error': 'Invalid state'}), 400
    db.save_tour_state(state)
    return jsonify({'success': True})

@app.route('/api/hub/school/timetable/entries', methods=['GET'])
def get_timetable_entries():

    day = request.args.get('day', type=int)
    week = _bounded_str(request.args.get('week'))
    user_id = request.args.get('user_id')
    entries = db.get_timetable_entries(day=day, week=week, user_id=user_id)
    return jsonify({'success': True, 'entries': entries})

@app.route('/api/hub/school/timetable/entries', methods=['POST'])
def create_timetable_entry():

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    if not data.get('day') or not data.get('block') or not data.get('subject'):
        return jsonify({'success': False, 'error': 'day, block, and subject are required'}), 400

    entry_id = db.create_timetable_entry(
        day=data['day'],
        block=data['block'],
        subject=data['subject'],
        week=data.get('week', 'both'),
        subject_type=data.get('subject_type', 'GK'),
        room=data.get('room'),
        teacher=data.get('teacher'),
        color=data.get('color'),
        user_id=data.get('user_id')
    )
    entry = db.get_timetable_entry(entry_id)
    return jsonify({'success': True, 'entry': entry})

@app.route('/api/hub/school/timetable/entries/<int:entry_id>', methods=['GET'])
def get_timetable_entry(entry_id):

    entry = db.get_timetable_entry(entry_id)
    if not entry:
        return jsonify({'success': False, 'error': 'Entry not found'}), 404
    return jsonify({'success': True, 'entry': entry})

@app.route('/api/hub/school/timetable/entries/<int:entry_id>', methods=['PUT'])
def update_timetable_entry(entry_id):

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    success = db.update_timetable_entry(
        entry_id,
        day=data.get('day'),
        block=data.get('block'),
        subject=data.get('subject'),
        week=data.get('week'),
        subject_type=data.get('subject_type'),
        room=data.get('room'),
        teacher=data.get('teacher'),
        color=data.get('color')
    )

    if not success:
        return jsonify({'success': False, 'error': 'Entry not found'}), 404

    entry = db.get_timetable_entry(entry_id)
    return jsonify({'success': True, 'entry': entry})

@app.route('/api/hub/school/timetable/entries/<int:entry_id>', methods=['DELETE'])
def delete_timetable_entry(entry_id):

    success = db.delete_timetable_entry(entry_id)
    if not success:
        return jsonify({'success': False, 'error': 'Entry not found'}), 404
    return jsonify({'success': True})

@app.route('/api/hub/school/timetable/clear', methods=['POST'])
def clear_timetable():

    data = request.get_json() or {}
    user_id = data.get('user_id')
    count = db.clear_timetable(user_id=user_id)
    return jsonify({'success': True, 'deleted': count})

@app.route('/api/hub/school/timetable/import', methods=['POST'])
def import_timetable_template():

    data = request.get_json()
    if not data or 'entries' not in data:
        return jsonify({'success': False, 'error': 'No entries provided'}), 400

    user_id = data.get('user_id')
    if data.get('clear_existing', False):
        db.clear_timetable(user_id=user_id)

    count = db.import_timetable_template(data['entries'], user_id=user_id)
    return jsonify({'success': True, 'imported': count})

DEFAULT_TIMETABLE_TEMPLATE = [

    {'day': 1, 'block': 1, 'week': 'A', 'subject': 'Deutsch', 'subject_type': 'LK', 'room': '226', 'color': '#4285f4'},
    {'day': 1, 'block': 2, 'week': 'A', 'subject': 'Geschichte', 'subject_type': 'GK', 'room': '124', 'color': '#ea4335'},
    {'day': 1, 'block': 3, 'week': 'A', 'subject': 'Englisch', 'subject_type': 'GK', 'room': '330', 'color': '#34a853'},
    {'day': 1, 'block': 4, 'week': 'A', 'subject': 'Sport', 'subject_type': 'GK', 'room': 'TH', 'color': '#ff9800'},

    {'day': 2, 'block': 1, 'week': 'A', 'subject': 'Physik', 'subject_type': 'GK', 'room': '310', 'color': '#9c27b0'},
    {'day': 2, 'block': 2, 'week': 'A', 'subject': 'Mathe', 'subject_type': 'LK', 'room': '420', 'color': '#e91e63'},
    {'day': 2, 'block': 3, 'week': 'A', 'subject': 'Deutsch', 'subject_type': 'LK', 'room': '226', 'color': '#4285f4'},
    {'day': 2, 'block': 4, 'week': 'A', 'subject': 'Seminar', 'subject_type': 'SK', 'room': '226', 'color': '#607d8b'},

    {'day': 3, 'block': 1, 'week': 'A', 'subject': 'PB', 'subject_type': 'GK', 'room': '124', 'color': '#00bcd4'},
    {'day': 3, 'block': 2, 'week': 'A', 'subject': 'Geschichte', 'subject_type': 'GK', 'room': '124', 'color': '#ea4335'},
    {'day': 3, 'block': 3, 'week': 'A', 'subject': 'Mathe', 'subject_type': 'LK', 'room': '420', 'color': '#e91e63'},

    {'day': 4, 'block': 1, 'week': 'A', 'subject': 'Informatik', 'subject_type': 'GK', 'room': 'PC1', 'color': '#795548'},
    {'day': 4, 'block': 2, 'week': 'A', 'subject': 'Mathe', 'subject_type': 'LK', 'room': '420', 'color': '#e91e63'},
    {'day': 4, 'block': 3, 'week': 'A', 'subject': 'Englisch', 'subject_type': 'GK', 'room': '330', 'color': '#34a853'},
    {'day': 4, 'block': 4, 'week': 'A', 'subject': 'Chemie', 'subject_type': 'GK', 'room': '301', 'color': '#8bc34a'},

    {'day': 5, 'block': 1, 'week': 'A', 'subject': 'Sport', 'subject_type': 'GK', 'room': 'TH', 'color': '#ff9800'},
    {'day': 5, 'block': 2, 'week': 'A', 'subject': 'Deutsch', 'subject_type': 'LK', 'room': '226', 'color': '#4285f4'},
    {'day': 5, 'block': 3, 'week': 'A', 'subject': 'Physik', 'subject_type': 'GK', 'room': '310', 'color': '#9c27b0'},

    {'day': 1, 'block': 1, 'week': 'B', 'subject': 'Englisch', 'subject_type': 'GK', 'room': '330', 'color': '#34a853'},
    {'day': 1, 'block': 2, 'week': 'B', 'subject': 'PB', 'subject_type': 'GK', 'room': '124', 'color': '#00bcd4'},
    {'day': 1, 'block': 3, 'week': 'B', 'subject': 'Deutsch', 'subject_type': 'LK', 'room': '226', 'color': '#4285f4'},
    {'day': 1, 'block': 4, 'week': 'B', 'subject': 'Chemie', 'subject_type': 'GK', 'room': '301', 'color': '#8bc34a'},

    {'day': 2, 'block': 1, 'week': 'B', 'subject': 'Informatik', 'subject_type': 'GK', 'room': 'PC1', 'color': '#795548'},
    {'day': 2, 'block': 2, 'week': 'B', 'subject': 'Mathe', 'subject_type': 'LK', 'room': '420', 'color': '#e91e63'},
    {'day': 2, 'block': 3, 'week': 'B', 'subject': 'Geschichte', 'subject_type': 'GK', 'room': '124', 'color': '#ea4335'},
    {'day': 2, 'block': 4, 'week': 'B', 'subject': 'Seminar', 'subject_type': 'SK', 'room': '226', 'color': '#607d8b'},

    {'day': 3, 'block': 1, 'week': 'B', 'subject': 'Physik', 'subject_type': 'GK', 'room': '310', 'color': '#9c27b0'},
    {'day': 3, 'block': 2, 'week': 'B', 'subject': 'Mathe', 'subject_type': 'LK', 'room': '420', 'color': '#e91e63'},
    {'day': 3, 'block': 3, 'week': 'B', 'subject': 'Deutsch', 'subject_type': 'LK', 'room': '226', 'color': '#4285f4'},

    {'day': 4, 'block': 1, 'week': 'B', 'subject': 'Sport', 'subject_type': 'GK', 'room': 'TH', 'color': '#ff9800'},
    {'day': 4, 'block': 2, 'week': 'B', 'subject': 'Englisch', 'subject_type': 'GK', 'room': '330', 'color': '#34a853'},
    {'day': 4, 'block': 3, 'week': 'B', 'subject': 'Mathe', 'subject_type': 'LK', 'room': '420', 'color': '#e91e63'},

    {'day': 5, 'block': 1, 'week': 'B', 'subject': 'Deutsch', 'subject_type': 'LK', 'room': '226', 'color': '#4285f4'},
    {'day': 5, 'block': 2, 'week': 'B', 'subject': 'Geschichte', 'subject_type': 'GK', 'room': '124', 'color': '#ea4335'},
]

@app.route('/api/hub/school/timetable/default-template', methods=['GET'])
def get_default_timetable_template():

    return jsonify({'success': True, 'template': DEFAULT_TIMETABLE_TEMPLATE})

@app.route('/api/hub/school/timetable/periods', methods=['GET'])
def get_timetable_periods():
    periods = db.get_timetable_periods()
    return jsonify({'periods': periods})

@app.route('/api/hub/school/timetable/periods/replace-all', methods=['POST'])
def replace_all_timetable_periods():
    data = request.get_json()
    if not data or 'periods' not in data:
        return jsonify({'error': 'No periods provided'}), 400

    periods = data['periods']
    if not isinstance(periods, list) or len(periods) == 0 or len(periods) > 12:
        return jsonify({'error': 'Periods must be a list of 1-12 items'}), 400

    import re
    time_pattern = re.compile(r'^\d{2}:\d{2}$')
    validated = []
    for p in periods:
        pn = p.get('period_number')
        st = p.get('start_time', '')
        et = p.get('end_time', '')
        if not isinstance(pn, int) or pn < 1 or pn > 12:
            return jsonify({'error': f'Invalid period_number: {pn}'}), 400
        if not time_pattern.match(st) or not time_pattern.match(et):
            return jsonify({'error': f'Invalid time format for period {pn}'}), 400
        validated.append({'period_number': pn, 'start_time': st, 'end_time': et})

    db.replace_all_timetable_periods(validated)

    # Update block_count in timetable settings
    conn = db.get_connection()
    existing = conn.execute('SELECT id FROM hub_timetable_settings LIMIT 1').fetchone()
    if existing:
        conn.execute('UPDATE hub_timetable_settings SET block_count = ? WHERE id = ?',
                     [len(validated), existing['id']])
    else:
        conn.execute('INSERT INTO hub_timetable_settings (block_count) VALUES (?)', [len(validated)])
    conn.commit()
    conn.close()

    return jsonify({'success': True, 'periods': validated})

@app.route('/api/hub/school/timetable/periods/<int:period_number>', methods=['DELETE'])
def delete_timetable_period(period_number):
    deleted = db.delete_timetable_period(period_number)
    if not deleted:
        return jsonify({'error': 'Period not found'}), 404
    return jsonify({'success': True})

QUICK_NOTES_FILE = DATA_DIR / 'quick_notes.json'

def load_quick_notes():
    try:
        return decrypt_file(QUICK_NOTES_FILE) or []
    except Exception:
        return []

def save_quick_notes(notes):
    encrypt_file(notes, QUICK_NOTES_FILE)

@app.route('/api/hub/quick-notes', methods=['GET'])
def get_quick_notes():
    notes = load_quick_notes()
    return jsonify({'notes': notes})

@app.route('/api/hub/quick-notes', methods=['POST'])
def create_quick_note():
    data = request.json
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    notes = load_quick_notes()

    note = {
        'id': str(uuid.uuid4()),
        'type': data.get('type', 'note'),
        'title': data.get('title'),
        'content': data.get('content'),
        'created_at': datetime.now().isoformat()
    }

    notes.append(note)
    save_quick_notes(notes)
    return jsonify({'note': note})

@app.route('/api/hub/quick-notes/<note_id>', methods=['DELETE'])
def delete_quick_note(note_id):
    notes = load_quick_notes()
    notes = [n for n in notes if n['id'] != note_id]
    save_quick_notes(notes)
    return jsonify({'success': True})

@app.route('/api/hub/training/sessions', methods=['GET'])
def get_training_sessions():

    session_type = request.args.get('type')
    sessions = db.get_hub_training_sessions(session_type=session_type)
    return jsonify({'sessions': sessions})

@app.route('/api/hub/training/sessions', methods=['POST'])
def create_training_session():

    data = request.json
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    exercises = data.get('exercises')
    if isinstance(exercises, (list, dict)):
        exercises = json.dumps(exercises)

    session_id = db.create_hub_training_session(
        session_type=data.get('type'),
        date=data.get('date'),
        duration=data.get('duration'),
        notes=data.get('notes'),
        calories=data.get('calories'),
        exercises=exercises
    )
    session = db.get_hub_training_session(session_id)
    return jsonify({'success': True, 'session': session})

@app.route('/api/hub/training/sessions/<int:session_id>', methods=['GET'])
def get_training_session(session_id):

    session = db.get_hub_training_session(session_id)
    if not session:
        return jsonify({'success': False, 'error': 'Session not found'}), 404
    return jsonify({'success': True, 'session': session})

@app.route('/api/hub/training/sessions/<int:session_id>', methods=['PUT'])
def update_training_session(session_id):

    data = request.json
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    session = db.get_hub_training_session(session_id)
    if not session:
        return jsonify({'success': False, 'error': 'Session not found'}), 404

    exercises = data.get('exercises')
    if isinstance(exercises, (list, dict)):
        exercises = json.dumps(exercises)

    db.update_hub_training_session(
        session_id,
        session_type=data.get('type'),
        date=data.get('date'),
        duration=data.get('duration'),
        notes=data.get('notes'),
        calories=data.get('calories'),
        exercises=exercises
    )
    updated_session = db.get_hub_training_session(session_id)
    return jsonify({'success': True, 'session': updated_session})

@app.route('/api/hub/training/sessions/<int:session_id>', methods=['DELETE'])
def delete_training_session(session_id):

    db.delete_hub_training_session(session_id)
    return jsonify({'success': True})

@app.route('/api/hub/training/health', methods=['GET'])
def get_training_health():

    logs = db.get_hub_training_health()
    return jsonify({'logs': logs})

@app.route('/api/hub/training/health', methods=['POST'])
def create_training_health():

    data = request.json
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    date = data.get('date')

    existing = db.get_hub_training_health_by_date(date)

    if existing:

        db.update_hub_training_health(
            existing['id'],
            sleep=data.get('sleep'),
            energy=data.get('energy'),
            stress=data.get('stress'),
            recovery=data.get('recovery'),
            weight=data.get('weight'),
            notes=data.get('notes')
        )
    else:

        db.create_hub_training_health(
            date=date,
            sleep=data.get('sleep'),
            energy=data.get('energy'),
            stress=data.get('stress'),
            recovery=data.get('recovery'),
            weight=data.get('weight'),
            notes=data.get('notes')
        )

    return jsonify({'success': True})

@app.route('/api/hub/training/health/<int:log_id>', methods=['GET'])
def get_training_health_entry(log_id):
    log = db.get_hub_training_health_by_id(log_id)
    if not log:
        return jsonify({'success': False, 'error': 'Health log not found'}), 404
    return jsonify({'success': True, 'log': log})

@app.route('/api/hub/training/health/<int:log_id>', methods=['PUT'])
def update_training_health_entry(log_id):
    data = request.json
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    log = db.get_hub_training_health_by_id(log_id)
    if not log:
        return jsonify({'success': False, 'error': 'Health log not found'}), 404

    db.update_hub_training_health(
        log_id,
        sleep=data.get('sleep'),
        energy=data.get('energy'),
        stress=data.get('stress'),
        recovery=data.get('recovery'),
        weight=data.get('weight'),
        notes=data.get('notes')
    )
    return jsonify({'success': True})

@app.route('/api/hub/training/health/<int:log_id>', methods=['DELETE'])
def delete_training_health_entry(log_id):
    db.delete_hub_training_health(log_id)
    return jsonify({'success': True})

@app.route('/api/hub/training/goals', methods=['GET'])
def get_training_goals():

    completed = request.args.get('completed')
    if completed is not None:
        completed = completed.lower() == 'true'
    goals = db.get_hub_training_goals(completed=completed)
    return jsonify({'goals': goals})

@app.route('/api/hub/training/goals', methods=['POST'])
def create_training_goal():

    data = request.json
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    goal_id = db.create_hub_training_goal(
        title=data.get('title'),
        target=data.get('target'),
        current=data.get('current', 0),
        unit=data.get('unit'),
        deadline=data.get('deadline')
    )
    goal = db.get_hub_training_goal(goal_id)
    return jsonify({'success': True, 'goal': goal})

@app.route('/api/hub/training/goals/<int:goal_id>', methods=['GET'])
def get_training_goal(goal_id):

    goal = db.get_hub_training_goal(goal_id)
    if not goal:
        return jsonify({'success': False, 'error': 'Goal not found'}), 404
    return jsonify({'success': True, 'goal': goal})

@app.route('/api/hub/training/goals/<int:goal_id>', methods=['PUT'])
def update_training_goal(goal_id):

    data = request.json
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    goal = db.get_hub_training_goal(goal_id)
    if not goal:
        return jsonify({'success': False, 'error': 'Goal not found'}), 404

    db.update_hub_training_goal(
        goal_id,
        title=data.get('title'),
        target=data.get('target'),
        current=data.get('current'),
        unit=data.get('unit'),
        deadline=data.get('deadline'),
        completed=data.get('completed')
    )
    updated_goal = db.get_hub_training_goal(goal_id)
    return jsonify({'success': True, 'goal': updated_goal})

@app.route('/api/hub/training/goals/<int:goal_id>', methods=['DELETE'])
def delete_training_goal(goal_id):

    db.delete_hub_training_goal(goal_id)
    return jsonify({'success': True})

@app.route('/api/hub/training/holiday-check', methods=['GET'])
def check_holiday_mode():
    from datetime import datetime

    today = datetime.now().date()
    today_str = today.strftime('%Y-%m-%d')

    holiday_keywords = [
        'ferien',
        'schulferien',
        'herbstferien',
        'winterferien',
        'osterferien',
        'sommerferien',
        'weihnachtsferien',
        'pfingstferien',
        'frühjahrsferien',
        'urlaub',
        'vacation',
        'school holiday',
    ]

    def check_event_is_holiday(event):

        title = (event.get('title') or event.get('summary') or '').lower()

        calendar = (event.get('calendar') or event.get('calendar_id') or '').lower()
        if 'holiday@group' in calendar or 'feiertage' in calendar:
            return False

        return any(keyword in title for keyword in holiday_keywords)

    def event_covers_today(event):

        start = event.get('date') or event.get('start_date') or ''
        end = event.get('end_date') or event.get('end') or start

        if isinstance(start, dict):
            start = start.get('date') or start.get('dateTime', '')[:10]
        if isinstance(end, dict):
            end = end.get('date') or end.get('dateTime', '')[:10]

        if 'T' in str(start):
            start = str(start).split('T')[0]
        if 'T' in str(end):
            end = str(end).split('T')[0]

        try:
            return start <= today_str <= (end or start)
        except Exception:
            return False

    is_holiday = False
    source = None

    try:
        school_events = load_school_calendar()
        for event in school_events:
            if event_covers_today(event) and check_event_is_holiday(event):
                is_holiday = True
                source = 'school_calendar'
                break
    except Exception as e:
        logging.warning("School calendar check failed: %s", e)

    if not is_holiday:
        try:
            from .google_oauth import fetch_google_calendar_events, load_tokens

            tokens = load_tokens()
            if tokens:

                result = fetch_google_calendar_events(
                    days_ahead=1,
                    start_date=today_str,
                    end_date=today_str
                )

                if result.get('success'):
                    for event in result.get('events', []):
                        if check_event_is_holiday(event):
                            is_holiday = True
                            source = 'google_calendar'
                            break
        except Exception as e:
            logging.warning("Google Calendar check failed: %s", e)

    return jsonify({
        'is_holiday': is_holiday,
        'source': source,
        'date': today_str
    })

@app.route('/api/hub/training/schedule/settings', methods=['GET'])
def get_training_schedule_settings_route():

    user_id = request.args.get('user_id')
    settings = db.get_training_schedule_settings(user_id=user_id)
    if settings:
        return jsonify({'success': True, 'settings': settings})
    return jsonify({'success': True, 'settings': None, 'setup_required': True})

@app.route('/api/hub/training/schedule/settings', methods=['POST'])
def save_training_schedule_settings_route():

    data = request.get_json(silent=True)
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400
    settings_id = db.save_training_schedule_settings(
        schedule_mode=data.get('schedule_mode', 'regular'),
        auto_detect_holiday=data.get('auto_detect_holiday', True),
        setup_completed=data.get('setup_completed', False),
        user_id=data.get('user_id')
    )
    return jsonify({'success': True, 'settings_id': settings_id})

@app.route('/api/hub/training/schedule/entries', methods=['GET'])
def get_training_schedule_entries_route():

    day = request.args.get('day', type=int)
    schedule_type = request.args.get('schedule_type')
    user_id = request.args.get('user_id')
    entries = db.get_training_schedule_entries(day=day, schedule_type=schedule_type, user_id=user_id)
    return jsonify({'success': True, 'entries': entries})

@app.route('/api/hub/training/schedule/entries', methods=['POST'])
def create_training_schedule_entry_route():

    data = request.get_json(silent=True)
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400
    if data.get('day') is None or not data.get('training_type') or not data.get('title'):
        return jsonify({'success': False, 'error': 'day, training_type, and title are required'}), 400

    entry_id = db.create_training_schedule_entry(
        day=data['day'],
        training_type=data['training_type'],
        title=data['title'],
        schedule_type=data.get('schedule_type', 'regular'),
        time=data.get('time'),
        duration=data.get('duration'),
        location=data.get('location'),
        muscle_groups=data.get('muscle_groups'),
        notes=data.get('notes'),
        icon=data.get('icon'),
        color=data.get('color'),
        user_id=data.get('user_id')
    )
    entry = db.get_training_schedule_entry(entry_id)
    return jsonify({'success': True, 'entry': entry})

@app.route('/api/hub/training/schedule/entries/<int:entry_id>', methods=['GET'])
def get_training_schedule_entry_route(entry_id):
    entry = db.get_training_schedule_entry(entry_id)
    if entry:
        return jsonify({'success': True, 'entry': entry})
    return jsonify({'success': False, 'error': 'Entry not found'}), 404

@app.route('/api/hub/training/schedule/entries/<int:entry_id>', methods=['PUT'])
def update_training_schedule_entry_route(entry_id):
    data = request.get_json(silent=True)
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400
    success = db.update_training_schedule_entry(
        entry_id=entry_id,
        day=data.get('day'),
        schedule_type=data.get('schedule_type'),
        training_type=data.get('training_type'),
        title=data.get('title'),
        time=data.get('time'),
        duration=data.get('duration'),
        location=data.get('location'),
        muscle_groups=data.get('muscle_groups'),
        notes=data.get('notes'),
        icon=data.get('icon'),
        color=data.get('color')
    )
    if success:
        entry = db.get_training_schedule_entry(entry_id)
        return jsonify({'success': True, 'entry': entry})
    return jsonify({'success': False, 'error': 'Entry not found'}), 404

@app.route('/api/hub/training/schedule/entries/<int:entry_id>', methods=['DELETE'])
def delete_training_schedule_entry_route(entry_id):
    success = db.delete_training_schedule_entry(entry_id)
    if success:
        return jsonify({'success': True})
    return jsonify({'success': False, 'error': 'Entry not found'}), 404

@app.route('/api/hub/training/schedule/clear', methods=['POST'])
def clear_training_schedule_route():

    data = request.get_json() or {}
    schedule_type = data.get('schedule_type')
    user_id = data.get('user_id')
    count = db.clear_training_schedule(schedule_type, user_id=user_id)
    return jsonify({'success': True, 'deleted': count})

@app.route('/api/hub/training/schedule/import', methods=['POST'])
def import_training_schedule_route():

    data = request.get_json()
    if not data or not data.get('entries'):
        return jsonify({'success': False, 'error': 'entries required'}), 400

    user_id = data.get('user_id')
    if data.get('clear_existing', False):
        db.clear_training_schedule(data.get('schedule_type'), user_id=user_id)

    count = db.import_training_schedule_template(data['entries'], user_id=user_id)
    return jsonify({'success': True, 'imported': count})

@app.route('/api/email/accounts', methods=['GET'])
def get_email_accounts_route():
    from .email_service import get_email_accounts
    from .google_oauth import get_google_accounts
    from .iserv_service import get_iserv_service

    imap_accounts = get_email_accounts()
    google_accounts = get_google_accounts()

    iserv_accounts = []
    iserv_service = get_iserv_service()
    status = iserv_service.get_status()
    if status.get('connected') or status.get('has_credentials'):
        username = status.get('username', 'IServ')
        iserv_accounts = [{
            'email': f'{username}@iserv',
            'provider': 'iserv',
            'display_name': f'IServ ({username})'
        }]

    return jsonify(imap_accounts + google_accounts + iserv_accounts)

@app.route('/api/email/accounts', methods=['POST'])
def add_email_account_route():
    from .email_service import add_email_account
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    email = data.get('email', '').strip()
    password = data.get('password', '')
    provider = data.get('provider', '')

    if not email or not password or not provider:
        return jsonify({'error': 'Email, password, and provider are required'}), 400

    result = add_email_account(email, password, provider)
    if result['success']:
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/email/accounts/<path:email>', methods=['DELETE'])
def remove_email_account_route(email):
    from .email_service import remove_email_account
    from .google_oauth import remove_google_account, get_google_accounts

    google_accounts = [a['email'] for a in get_google_accounts()]
    if email in google_accounts:
        success = remove_google_account(email)
    else:
        success = remove_email_account(email)

    if success:
        return jsonify({'success': True})
    return jsonify({'error': 'Account not found'}), 404

@app.route('/api/email/folders/<path:email>', methods=['GET'])
def get_email_folders_route(email):
    from .email_service import get_folders
    result = get_folders(email)
    if result['success']:
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/email/messages/<path:email>', methods=['GET'])
def get_email_messages_route(email):
    from .email_service import fetch_emails
    from .google_oauth import get_google_accounts, fetch_gmail_messages
    from .iserv_service import get_iserv_service

    if email.endswith('@iserv'):
        iserv_service = get_iserv_service()
        if not iserv_service.is_connected():

            iserv_service.connect()
        limit = min(max(request.args.get('limit', 20, type=int), 1), 200)
        result = iserv_service.get_emails(limit=limit)
        if result.get('success'):

            emails = result.get('emails', [])
            transformed = []
            for e in emails:
                transformed.append({
                    'id': e.get('uid') or e.get('id') or str(hash(e.get('subject', ''))),
                    'from': e.get('from', e.get('sender', '')),
                    'from_name': e.get('from_name', e.get('from', '').split('@')[0]),
                    'subject': e.get('subject', '(Kein Betreff)'),
                    'date': e.get('date', ''),
                    'preview': e.get('preview', e.get('snippet', '')),
                    'read': e.get('read', not e.get('unseen', False))
                })
            return jsonify({'success': True, 'emails': transformed})
        return jsonify(result), 400

    google_accounts = [a['email'] for a in get_google_accounts()]
    if email in google_accounts:
        limit = min(max(request.args.get('limit', 20, type=int), 1), 200)
        result = fetch_gmail_messages(email, limit)
    else:
        folder = request.args.get('folder', 'INBOX')
        limit = min(max(request.args.get('limit', 20, type=int), 1), 200)
        result = fetch_emails(email, folder, limit)

    if result['success']:
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/email/message/<path:email>/<msg_id>', methods=['GET'])
def get_email_detail_route(email, msg_id):
    from .email_service import get_email_detail
    from .google_oauth import get_google_accounts, get_gmail_message_detail
    from .iserv_service import get_iserv_service

    if email.endswith('@iserv'):
        iserv_service = get_iserv_service()
        if not iserv_service.is_connected():
            iserv_service.connect()
        result = iserv_service.get_email_detail(msg_id)
        if result.get('success'):
            return jsonify(result)
        return jsonify(result), 400

    google_accounts = [a['email'] for a in get_google_accounts()]
    if email in google_accounts:
        result = get_gmail_message_detail(email, msg_id)
    else:
        folder = request.args.get('folder', 'INBOX')
        result = get_email_detail(email, msg_id, folder)

    if result['success']:
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/email/send', methods=['POST'])
def send_email_route():
    from .email_service import send_email
    from .google_oauth import get_google_accounts, send_gmail
    from .iserv_service import get_iserv_service
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    from_email = data.get('from_email', data.get('from', '')).strip()
    to_email = data.get('to_email', data.get('to', '')).strip()
    subject = data.get('subject', '').strip()
    body = data.get('body', '')

    if not from_email or not to_email or not subject:
        return jsonify({'error': 'From, to, and subject are required'}), 400

    if from_email.endswith('@iserv'):
        iserv_service = get_iserv_service()
        if not iserv_service.is_connected():
            iserv_service.connect()
        result = iserv_service.send_email(to=to_email, subject=subject, body=body)
        if result.get('success'):
            return jsonify(result)
        return jsonify(result), 400

    google_accounts = [a['email'] for a in get_google_accounts()]
    if from_email in google_accounts:
        result = send_gmail(from_email, to_email, subject, body)
    else:
        result = send_email(from_email, to_email, subject, body)

    if result['success']:
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/email/google/status', methods=['GET'])
def google_oauth_status():

    from .google_oauth import get_oauth_status
    return jsonify(get_oauth_status())

@app.route('/api/email/google/auth', methods=['POST'])
def start_google_auth():

    from .google_oauth import start_oauth_flow
    result = start_oauth_flow()
    if result.get('success'):
        session['oauth_state'] = result.get('state')
    return jsonify(result)

@app.route('/api/email/google/callback', methods=['POST'])
def complete_google_auth():

    from .google_oauth import complete_oauth_flow
    data = request.get_json()
    if not data or not data.get('code'):
        return jsonify({'success': False, 'error': 'Authorization code required'}), 400
    state = data.get('state', '')
    expected_state = session.get('oauth_state') or ''
    if not state or not expected_state or not _same_secret(state, expected_state):
        return jsonify({'success': False, 'error': 'Invalid state parameter'}), 403
    session.pop('oauth_state', None)
    result = complete_oauth_flow(data['code'])
    return jsonify(result)

@app.route('/api/email/google/oauth-callback', methods=['GET'])
def google_oauth_redirect_callback():

    from .google_oauth import complete_oauth_flow

    code = request.args.get('code')
    error = request.args.get('error')
    state = request.args.get('state')
    expected_state = session.get('oauth_state')

    nonce = g.csp_nonce

    if not state or not expected_state or not _same_secret(state, expected_state):
        return f'''
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
            <h2 style="color: #d93025;">Invalid Request</h2>
            <p>OAuth state validation failed. Please try signing in again.</p>
            <script nonce="{nonce}">setTimeout(() => window.close(), 3000);</script>
        </body></html>
        '''

    session.pop('oauth_state', None)

    if error:
        safe_error = html_mod.escape(error)
        return f'''
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
            <h2 style="color: #d93025;">Authorization Failed</h2>
            <p>Error: {safe_error}</p>
            <p>You can close this window and try again.</p>
            <script nonce="{nonce}">setTimeout(() => window.close(), 3000);</script>
        </body></html>
        '''

    if not code:
        return f'''
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
            <h2 style="color: #d93025;">No Authorization Code</h2>
            <p>No authorization code received from Google.</p>
            <script nonce="{nonce}">setTimeout(() => window.close(), 3000);</script>
        </body></html>
        '''

    result = complete_oauth_flow(code)

    if result.get('success'):
        safe_email = html_mod.escape(result.get('email', 'your account'))
        js_email = safe_email.replace('\\', '\\\\').replace("'", "\\'")
        return f'''
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
            <h2 style="color: #34a853;">Successfully Connected!</h2>
            <p>Connected: <strong>{safe_email}</strong></p>
            <p>You can close this window and return to {html_mod.escape(brand.NAME)}.</p>
            <script nonce="{nonce}">
                if (window.opener) {{
                    window.opener.postMessage({{ type: 'google-oauth-success', email: '{js_email}' }}, window.location.origin);
                }}
                setTimeout(() => window.close(), 2000);
            </script>
        </body></html>
        '''
    else:
        safe_error_msg = html_mod.escape(result.get('error', 'Unknown error'))
        return f'''
        <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
            <h2 style="color: #d93025;">Connection Failed</h2>
            <p>{safe_error_msg}</p>
            <p>Please close this window and try again.</p>
            <script nonce="{nonce}">setTimeout(() => window.close(), 5000);</script>
        </body></html>
        '''

@app.route('/api/email/google/accounts', methods=['GET'])
def list_google_accounts():

    from .google_oauth import get_google_accounts
    accounts = get_google_accounts()
    return jsonify({'accounts': accounts})

@app.route('/api/email/google/remove/<path:email>', methods=['DELETE'])
def remove_google_account_route(email):

    from .google_oauth import remove_google_account
    success = remove_google_account(email)
    return jsonify({'success': success})

@app.route('/api/calendar/events', methods=['GET'])
def get_calendar_events():

    from .google_oauth import fetch_google_calendar_events, load_tokens

    start_date = request.args.get('start')
    end_date = request.args.get('end')
    days = min(max(request.args.get('days', 14, type=int), 1), 365)
    account = request.args.get('account')

    tokens = load_tokens()
    if tokens:
        result = fetch_google_calendar_events(
            days_ahead=days,
            account_email=account,
            start_date=start_date,
            end_date=end_date
        )
        if result.get('success'):
            return jsonify(result)

        if result.get('error') == 'scope_needed':
            return jsonify(result)

    from .calendar_service import get_macos_calendar_events
    result = get_macos_calendar_events(days)
    return jsonify(result)

@app.route('/api/calendar/macos', methods=['GET'])
def get_macos_calendar():

    from .calendar_service import get_macos_calendar_events
    days = min(max(request.args.get('days', 14, type=int), 1), 365)
    result = get_macos_calendar_events(days)
    return jsonify(result)

@app.route('/api/calendar/list', methods=['GET'])
def get_calendar_list():

    from .calendar_service import get_calendars
    result = get_calendars()
    return jsonify(result)

@app.route('/api/calendar/google/calendars', methods=['GET'])
def get_google_calendars_route():

    from .google_oauth import get_google_calendars
    account = request.args.get('account')
    result = get_google_calendars(account_email=account)
    return jsonify(result)

@app.route('/api/calendar/events', methods=['POST'])
def create_calendar_event():

    from .google_oauth import create_google_calendar_event
    data = request.get_json()

    if not data or not data.get('title') or not data.get('date'):
        return jsonify({'success': False, 'error': 'Title and date are required'}), 400

    result = create_google_calendar_event(
        title=data['title'],
        start_date=data['date'],
        start_time=data.get('time'),
        end_date=data.get('end_date'),
        end_time=data.get('end_time'),
        description=data.get('description'),
        location=data.get('location'),
        calendar_id=data.get('calendar_id', 'primary'),
        account_email=data.get('account')
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/calendar/events/<event_id>', methods=['PUT'])
def update_calendar_event(event_id):

    from .google_oauth import update_google_calendar_event
    data = request.get_json()

    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    result = update_google_calendar_event(
        event_id=event_id,
        title=data.get('title'),
        start_date=data.get('date'),
        start_time=data.get('time'),
        end_date=data.get('end_date'),
        end_time=data.get('end_time'),
        description=data.get('description'),
        location=data.get('location'),
        calendar_id=data.get('calendar_id', 'primary'),
        account_email=data.get('account')
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/calendar/events/<event_id>', methods=['DELETE'])
def delete_calendar_event(event_id):

    from .google_oauth import delete_google_calendar_event

    calendar_id = request.args.get('calendar_id', 'primary')
    account = request.args.get('account')
    delete_all = request.args.get('delete_all', 'false').lower() == 'true'
    recurring_event_id = request.args.get('recurring_event_id')

    result = delete_google_calendar_event(
        event_id=event_id,
        calendar_id=calendar_id,
        account_email=account,
        delete_all_occurrences=delete_all,
        recurring_event_id=recurring_event_id
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/calendar/caldav/accounts', methods=['GET'])
def get_caldav_accounts_route():

    from .calendar_service import get_caldav_accounts
    accounts = get_caldav_accounts()
    return jsonify({'success': True, 'accounts': accounts})

@app.route('/api/calendar/caldav/accounts', methods=['POST'])
def add_caldav_account_route():

    from .calendar_service import add_caldav_account
    data = request.get_json()

    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    result = add_caldav_account(
        name=data.get('name', ''),
        url=data.get('url', ''),
        username=data.get('username', ''),
        password=data.get('password', ''),
        provider=data.get('provider', 'caldav')
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/calendar/caldav/accounts/<account_id>', methods=['DELETE'])
def remove_caldav_account_route(account_id):

    from .calendar_service import remove_caldav_account
    result = remove_caldav_account(account_id)
    return jsonify(result)

@app.route('/api/calendar/caldav/events', methods=['GET'])
def get_caldav_events_route():

    from .calendar_service import fetch_caldav_events

    account_id = request.args.get('account_id')
    start_date = request.args.get('start')
    end_date = request.args.get('end')
    days = request.args.get('days', 30, type=int)
    days = min(max(days, 1), 365)

    result = fetch_caldav_events(
        account_id=account_id,
        days_ahead=days,
        start_date=start_date,
        end_date=end_date
    )

    return jsonify(result)

@app.route('/api/calendar/caldav/events', methods=['POST'])
def create_caldav_event_route():

    from .calendar_service import create_caldav_event
    data = request.get_json()

    if not data or not data.get('account_id') or not data.get('calendar_url'):
        return jsonify({'success': False, 'error': 'Account ID and calendar URL required'}), 400

    result = create_caldav_event(
        account_id=data['account_id'],
        calendar_url=data['calendar_url'],
        title=data.get('title', 'Untitled'),
        start_date=data.get('date'),
        start_time=data.get('time'),
        end_date=data.get('end_date'),
        end_time=data.get('end_time'),
        description=data.get('description', ''),
        location=data.get('location', '')
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/email/message/<path:email>/<msg_id>/read', methods=['POST'])
def mark_email_read_route(email, msg_id):
    from .email_service import mark_email_read

    result = mark_email_read(email, msg_id, request.args.get('folder', 'INBOX'))
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/email/message/<path:email>/<msg_id>', methods=['DELETE'])
def delete_email_message(email, msg_id):

    from .google_oauth import get_google_accounts, delete_gmail_message
    from .email_service import delete_email

    permanent = request.args.get('permanent', 'false').lower() == 'true'

    google_accounts = [a['email'] for a in get_google_accounts()]
    if email in google_accounts:
        result = delete_gmail_message(email, msg_id, permanent=permanent)
    else:

        result = delete_email(email, msg_id)

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/status', methods=['GET'])
def iserv_status():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    return jsonify(service.get_status())

@app.route('/api/iserv/connect', methods=['POST'])
def iserv_connect():

    from .iserv_service import get_iserv_service
    data = request.get_json() or {}
    service = get_iserv_service()

    result = service.connect(
        username=data.get('username'),
        password=data.get('password'),
        iserv_url=data.get('iserv_url')
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/disconnect', methods=['POST'])
def iserv_disconnect():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    service.delete_credentials()
    return jsonify({'success': True})

@app.route('/api/iserv/notifications', methods=['GET'])
def iserv_notifications():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    result = service.get_notifications()
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/badges', methods=['GET'])
def iserv_badges():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    result = service.get_badges()
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/emails', methods=['GET'])
def iserv_emails():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    folder = request.args.get('folder', 'INBOX')
    try:
        limit = int(request.args.get('limit', 20))
    except (ValueError, TypeError):
        limit = 20
    limit = min(max(limit, 1), 200)
    result = service.get_emails(folder=folder, limit=limit)
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/emails/send', methods=['POST'])
def iserv_send_email():

    from .iserv_service import get_iserv_service
    data = request.get_json() or {}
    service = get_iserv_service()

    result = service.send_email(
        to=data.get('to'),
        subject=data.get('subject'),
        body=data.get('body')
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/mail-folders', methods=['GET'])
def iserv_mail_folders():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    result = service.get_mail_folders()
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/events', methods=['GET'])
def iserv_events():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    result = service.get_upcoming_events()
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/events', methods=['POST'])
def iserv_create_event():

    from .iserv_service import get_iserv_service
    from datetime import datetime
    data = request.get_json() or {}
    service = get_iserv_service()

    try:
        start = datetime.fromisoformat(data.get('start'))
        end = datetime.fromisoformat(data.get('end')) if data.get('end') else None
    except (ValueError, TypeError):
        return jsonify({'success': False, 'error': 'Invalid date format'}), 400

    result = service.create_event(
        title=data.get('title'),
        start=start,
        end=end,
        description=data.get('description', ''),
        location=data.get('location', '')
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/exercises', methods=['GET'])
def iserv_exercises():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    result = service.get_exercises()
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/storage', methods=['GET'])
def iserv_storage():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    result = service.get_storage_info()
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/files', methods=['GET'])
def iserv_files():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    path = request.args.get('path', '/')
    import posixpath
    path = posixpath.normpath(path)
    if '..' in path:
        return jsonify({'success': False, 'error': 'Ungültiger Pfad'}), 400
    result = service.list_files(path=path)
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/users/search', methods=['GET'])
def iserv_search_users():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    query = _bounded_str(request.args.get('q', ''))
    result = service.search_users(query=query)
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/iserv/vertretungsplan', methods=['GET'])
def iserv_get_vertretungsplan():

    from .iserv_service import get_iserv_service
    service = get_iserv_service()
    display_id = min(max(request.args.get('display_id', 3, type=int), 1), 100)
    refresh = request.args.get('refresh', 'false').lower() == 'true'

    if refresh and service.is_connected():

        service.connect()

    result = service.get_vertretungsplan(display_id=display_id)
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/vbb/search', methods=['GET'])
def vbb_search_location():

    from .vbb_service import get_vbb_service
    service = get_vbb_service()
    query = _bounded_str(request.args.get('q', ''))
    if not query:
        return jsonify({'success': False, 'error': 'Suchbegriff fehlt'}), 400
    result = service.search_location(query)
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/vbb/nearby', methods=['GET'])
def vbb_nearby_stops():

    from .vbb_service import get_vbb_service
    service = get_vbb_service()
    try:
        lat = float(request.args.get('lat', 0))
        lng = float(request.args.get('lng', 0))
        radius = min(max(int(request.args.get('radius', 1000)), 100), 50000)
    except ValueError:
        return jsonify({'success': False, 'error': 'Ungültige Koordinaten'}), 400

    if lat == 0 or lng == 0:
        return jsonify({'success': False, 'error': 'Koordinaten fehlen'}), 400

    result = service.search_nearby_stops(lat, lng, radius)
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/vbb/route', methods=['POST'])
def vbb_get_route():

    from .vbb_service import get_vbb_service
    from datetime import datetime
    service = get_vbb_service()

    data = request.get_json() or {}

    from_location = data.get('from')
    to_location = data.get('to')

    if not from_location or not to_location:
        return jsonify({'success': False, 'error': 'Start und Ziel erforderlich'}), 400

    arrival_time = None
    departure_time = None

    if data.get('arrival'):
        try:
            arrival_time = datetime.fromisoformat(data['arrival'].replace('Z', '+00:00'))
        except ValueError:
            pass

    if data.get('departure'):
        try:
            departure_time = datetime.fromisoformat(data['departure'].replace('Z', '+00:00'))
        except ValueError:
            pass

    try:
        num_results = min(max(int(data.get('results', 6)), 1), 20)
    except (TypeError, ValueError):
        num_results = 6
    result = service.get_route(
        from_location=from_location,
        to_location=to_location,
        arrival_time=arrival_time,
        departure_time=departure_time,
        num_results=num_results
    )

    if result.get('success'):
        try:
            from .vbb_personalization import get_personalization
            pers = get_personalization()
            weights = pers.get_recommendation_weights()
            result['routes'] = service.score_routes(result['routes'], personalized_weights=weights)
            result['personalization'] = {
                'default_sort': pers.get_default_sort(),
            }
        except Exception:
            pass

        sort_by = data.get('sort', 'recommended')
        routes = result['routes']
        if sort_by == 'fastest':
            routes.sort(key=lambda r: r.get('duration', 9999))
        elif sort_by == 'cheapest':
            routes.sort(key=lambda r: r.get('price') or 9999)
        elif sort_by == 'fewest_transfers':
            routes.sort(key=lambda r: r.get('transfers', 99))
        result['routes'] = routes
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/vbb/route-to-event', methods=['POST'])
def vbb_route_to_event():

    from .vbb_service import get_vbb_service
    service = get_vbb_service()

    data = request.get_json() or {}

    event = data.get('event')
    current_location = data.get('current_location')
    buffer_minutes = data.get('buffer_minutes', 15)

    if not event:
        return jsonify({'success': False, 'error': 'Event erforderlich'}), 400

    if not current_location:
        return jsonify({'success': False, 'error': 'Aktueller Standort erforderlich'}), 400

    result = service.get_route_to_event(
        event=event,
        current_location=current_location,
        buffer_minutes=buffer_minutes
    )

    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/vbb/departures/<stop_id>', methods=['GET'])
def vbb_departures(stop_id):
    import re
    if not re.match(r'^[a-zA-Z0-9_:-]+$', stop_id):
        return jsonify({'success': False, 'error': 'Ungültige Haltestellen-ID'}), 400

    from .vbb_service import get_vbb_service
    service = get_vbb_service()
    try:
        duration = min(max(int(request.args.get('duration', 30)), 1), 120)
    except (ValueError, TypeError):
        duration = 30
    result = service.get_departures(stop_id, duration)
    if result.get('success'):
        return jsonify(result)
    return jsonify(result), 400

@app.route('/api/vbb/locations', methods=['GET'])
def vbb_get_known_locations():

    from .vbb_service import get_vbb_service
    service = get_vbb_service()
    return jsonify(service.get_known_locations())

@app.route('/api/vbb/locations', methods=['POST'])
def vbb_save_location():

    from .vbb_service import get_vbb_service
    service = get_vbb_service()
    data = request.get_json() or {}

    name = data.get('name')
    location = data.get('location')

    if not name or not location:
        return jsonify({'success': False, 'error': 'Name und Ort erforderlich'}), 400

    result = service.save_known_location(name, location)
    return jsonify(result)

@app.route('/api/vbb/locations', methods=['DELETE'])
def vbb_delete_location():

    from .vbb_service import get_vbb_service
    service = get_vbb_service()
    data = request.get_json() or {}
    name = data.get('name')
    if not name:
        return jsonify({'success': False, 'error': 'Name erforderlich'}), 400
    result = service.delete_known_location(name)
    return jsonify(result)


@app.route('/api/vbb/user-tickets', methods=['GET'])
def vbb_get_user_tickets():
    from .database import get_user_tickets
    tickets = get_user_tickets()
    return jsonify({'success': True, 'tickets': tickets})

@app.route('/api/vbb/user-tickets', methods=['POST'])
def vbb_create_user_ticket():
    from .database import create_user_ticket
    data = request.get_json() or {}
    required = ['ticket_type', 'ticket_name', 'zone_coverage']
    if not all(data.get(k) for k in required):
        return jsonify({'success': False, 'error': 'Ticket-Typ, Name und Tarifzone erforderlich'}), 400
    ticket_id = create_user_ticket(
        ticket_type=data['ticket_type'],
        ticket_name=data['ticket_name'],
        zone_coverage=data['zone_coverage'],
        valid_from=data.get('valid_from'),
        valid_until=data.get('valid_until'),
        auto_renews=data.get('auto_renews', False)
    )
    return jsonify({'success': True, 'id': ticket_id})

@app.route('/api/vbb/user-tickets/<int:ticket_id>', methods=['PUT'])
def vbb_update_user_ticket(ticket_id):
    from .database import update_user_ticket
    data = request.get_json() or {}
    key_map = {'name': 'ticket_name', 'type': 'ticket_type', 'zones': 'zone_coverage', 'auto_renews': 'auto_renews'}
    allowed = {}
    for k, v in data.items():
        db_key = key_map.get(k, k)
        if db_key in ('ticket_name', 'ticket_type', 'zone_coverage', 'valid_from', 'valid_until', 'auto_renews', 'is_active'):
            allowed[db_key] = v
    update_user_ticket(ticket_id, **allowed)
    return jsonify({'success': True})

@app.route('/api/vbb/user-tickets/<int:ticket_id>', methods=['DELETE'])
def vbb_delete_user_ticket(ticket_id):
    from .database import delete_user_ticket
    delete_user_ticket(ticket_id)
    return jsonify({'success': True})

@app.route('/api/vbb/check-ticket', methods=['POST'])
def vbb_check_ticket_coverage():
    from .vbb_service import get_vbb_service
    from .database import get_user_tickets
    service = get_vbb_service()
    data = request.get_json() or {}
    route = data.get('route')
    if not isinstance(route, dict):
        return jsonify({'success': False, 'error': 'Route erforderlich'}), 400
    tickets = get_user_tickets()
    result = service.check_ticket_coverage(route, tickets, data.get('travel_date'))
    return jsonify({'success': True, **result})

@app.route('/api/vbb/ticket-catalog', methods=['GET'])
def vbb_ticket_catalog():
    from .vbb_service import search_ticket_catalog, get_user_age, TICKET_CATEGORY_LABELS
    from .database import get_birthday_setting, get_timetable_settings
    query = _bounded_str(request.args.get('q', ''))
    age = request.args.get('age', type=int)
    if age is None:
        birthday = get_birthday_setting()
        settings = get_timetable_settings()
        graduation_date = settings.get('reference_date') if settings else None
        age = get_user_age(birthday, graduation_date)
    results = search_ticket_catalog(query, age)
    return jsonify({'success': True, 'tickets': results, 'category_labels': TICKET_CATEGORY_LABELS, 'user_age': age})

@app.route('/api/hub/birthday', methods=['GET'])
def get_birthday():
    from .database import get_birthday_setting
    birthday = get_birthday_setting()
    return jsonify({'success': True, 'birthday': birthday})

@app.route('/api/hub/birthday', methods=['POST'])
def save_birthday():
    from .database import save_birthday_setting
    data = request.get_json() or {}
    birthday = data.get('birthday', '')
    if birthday:
        try:
            from datetime import datetime
            datetime.strptime(birthday, '%Y-%m-%d')
        except ValueError:
            return jsonify({'success': False, 'error': 'Ungültiges Datumsformat'}), 400
    save_birthday_setting(birthday if birthday else None)
    return jsonify({'success': True, 'birthday': birthday})

@app.route('/api/hub/location', methods=['GET'])
def get_location():
    from .database import get_location_setting
    location_json = get_location_setting()
    if location_json:
        import json as _json
        try:
            return jsonify({'success': True, 'location': _json.loads(location_json)})
        except (ValueError, TypeError):
            pass
    return jsonify({'success': True, 'location': None})

@app.route('/api/hub/location', methods=['POST'])
def save_location_api():
    from .database import save_location_setting
    import json as _json
    data = request.get_json() or {}
    location = data.get('location')
    if not location or not isinstance(location, dict):
        return jsonify({'success': False, 'error': 'No location provided'}), 400
    city = location.get('city', '')
    lat = location.get('lat')
    lon = location.get('lon')
    if not city or lat is None or lon is None:
        return jsonify({'success': False, 'error': 'Missing city, lat, or lon'}), 400
    save_location_setting(_json.dumps({'city': city, 'lat': lat, 'lon': lon}))
    return jsonify({'success': True})


@app.route('/api/vbb/ticket-offers', methods=['POST'])
def vbb_ticket_offers():
    from .vbb_service import get_vbb_service
    service = get_vbb_service()

    data = request.get_json() or {}
    ctx_recon = data.get('ctxRecon')
    if not ctx_recon:
        return jsonify({'success': False, 'error': 'ctxRecon erforderlich'}), 400

    result = service.get_ticket_offers(ctx_recon)
    return jsonify(result)


@app.route('/api/vbb/monitor', methods=['POST'])
def vbb_start_monitoring():
    from .database import create_monitored_route
    data = request.get_json() or {}
    route = data.get('route')
    if not isinstance(route, dict):
        return jsonify({'success': False, 'error': 'Route erforderlich'}), 400

    from_name = ''
    to_name = ''
    legs = route.get('legs', [])
    if legs and isinstance(legs[0], dict):
        from_name = legs[0].get('departure', {}).get('station', '')
    if legs and isinstance(legs[-1], dict):
        to_name = legs[-1].get('arrival', {}).get('station', '')

    route_id = create_monitored_route(
        route_data=json.dumps(route),
        from_name=from_name,
        to_name=to_name,
        departure_time=route.get('departure', '')
    )

    if _start_route_monitor(route_id) is False:
        return jsonify({'success': False, 'error': 'Maximale Anzahl aktiver Monitore erreicht'}), 429

    return jsonify({'success': True, 'id': route_id, 'from': from_name, 'to': to_name})

@app.route('/api/vbb/monitor/<int:route_id>', methods=['GET'])
def vbb_get_monitor_status(route_id):
    from .database import get_monitored_routes
    routes = get_monitored_routes()
    route = next((r for r in routes if r['id'] == route_id), None)
    if not route:
        return jsonify({'success': False, 'error': 'Nicht gefunden'}), 404
    if route.get('current_delays'):
        route['current_delays'] = json.loads(route['current_delays'])
    if route.get('route_data'):
        route['route_data'] = json.loads(route['route_data'])
    return jsonify({'success': True, 'monitor': route})

@app.route('/api/vbb/monitor/<int:route_id>', methods=['DELETE'])
def vbb_stop_monitoring(route_id):
    from .database import update_monitored_route
    update_monitored_route(route_id, status='cancelled')
    return jsonify({'success': True})

@app.route('/api/vbb/monitor/<int:route_id>/check', methods=['GET'])
def vbb_force_check(route_id):
    from .database import get_monitored_routes
    routes = get_monitored_routes()
    route = next((r for r in routes if r['id'] == route_id), None)
    if not route:
        return jsonify({'success': False, 'error': 'Nicht gefunden'}), 404
    result = _check_monitored_route(route_id)
    return jsonify(result)


@app.route('/api/vbb/preferences', methods=['GET'])
def vbb_get_preferences():
    from .vbb_personalization import get_personalization
    pers = get_personalization()
    return jsonify({'success': True, 'preferences': pers.get_preferences()})

@app.route('/api/vbb/preferences/track', methods=['POST'])
def vbb_track_event():
    from .vbb_personalization import get_personalization
    data = request.get_json() or {}
    event = data.get('event')
    pers = get_personalization()

    if event == 'sort':
        pers.track_sort(
            data.get('sort_type', 'recommended'),
            from_id=data.get('from_id'),
            to_id=data.get('to_id'),
        )
    elif event == 'search':
        pers.track_search(
            data.get('from', {}),
            data.get('to', {}),
            data.get('departure'),
        )

    return jsonify({'success': True})

@app.route('/api/vbb/preferences/flags', methods=['PUT'])
def vbb_update_flags():
    from .vbb_personalization import get_personalization
    data = request.get_json() or {}
    get_personalization().update_flags(data.get('flags', {}))
    return jsonify({'success': True})

@app.route('/api/vbb/preferences/reset', methods=['POST'])
def vbb_reset_preferences():
    from .vbb_personalization import get_personalization
    get_personalization().reset()
    return jsonify({'success': True})

_active_monitors = {}
_MAX_MONITORS = 20

def _start_route_monitor(route_id):
    """Start background monitoring for a route."""
    if len(_active_monitors) >= _MAX_MONITORS:
        logging.warning(f"Monitor cap reached ({_MAX_MONITORS}), rejecting monitor for route {route_id}")
        return False

    def monitor_loop():
        from .database import get_monitored_routes, update_monitored_route
        from .vbb_service import get_vbb_service
        import time as _time

        service = get_vbb_service()

        while True:
            try:
                routes = get_monitored_routes()
                route = next((r for r in routes if r['id'] == route_id), None)
                if not route or route['status'] != 'active':
                    break

                dep_time_str = route.get('departure_time', '')
                if dep_time_str:
                    try:
                        dep_time = datetime.fromisoformat(dep_time_str.replace('Z', '+00:00'))
                        if datetime.now(dep_time.tzinfo) > dep_time + timedelta(minutes=30):
                            update_monitored_route(route_id, status='completed')
                            break
                    except (ValueError, TypeError):
                        pass

                route_data = json.loads(route['route_data'])
                check_result = service.check_route_connections(route_data)

                update_monitored_route(
                    route_id,
                    last_check=datetime.now().isoformat(),
                    current_delays=json.dumps(check_result)
                )

                if check_result.get('has_issues'):
                    for issue in check_result.get('issues', []):
                        event_type = 'vbb_connection_missed' if issue['type'] == 'missed' else 'vbb_delay_alert'
                        socketio.emit(event_type, {
                            'monitorId': route_id,
                            'type': issue['type'],
                            'line': issue.get('line', ''),
                            'station': issue.get('station', ''),
                            'delay': issue.get('delay', 0),
                            'message': issue.get('message', ''),
                            'from': route.get('from_name', ''),
                            'to': route.get('to_name', '')
                        })

            except Exception as e:
                logging.error(f"Route monitor error for {route_id}: {e}")

            _time.sleep(60)

        _active_monitors.pop(route_id, None)

    _active_monitors[route_id] = True
    socketio.start_background_task(monitor_loop)

def _check_monitored_route(route_id):
    """Force-check a monitored route."""
    from .database import get_monitored_routes, update_monitored_route
    from .vbb_service import get_vbb_service

    routes = get_monitored_routes()
    route = next((r for r in routes if r['id'] == route_id), None)
    if not route:
        return {'success': False, 'error': 'Nicht gefunden'}

    service = get_vbb_service()
    route_data = json.loads(route['route_data'])
    check_result = service.check_route_connections(route_data)

    update_monitored_route(
        route_id,
        last_check=datetime.now().isoformat(),
        current_delays=json.dumps(check_result)
    )

    return {'success': True, **check_result}

SYNCED_CALENDAR_FILE = DATA_DIR / 'synced_calendar.json'

@app.route('/api/calendar/local', methods=['GET'])
def get_local_calendar_events():

    try:
        data = decrypt_file(SYNCED_CALENDAR_FILE)
        if not data:
            return jsonify({
                'success': False,
                'error': 'Kalender nicht synchronisiert. Führe calendar_sync.py aus.'
            }), 404

        return jsonify({
            'success': True,
            'last_sync': data.get('last_sync'),
            'event_count': data.get('event_count', 0),
            'events': data.get('events', [])
        })
    except Exception as e:
        logging.error(f"Failed to read local calendar data: {e}")
        return jsonify({'success': False, 'error': 'Failed to load calendar data'}), 500

@app.route('/api/calendar/local/sync', methods=['POST'])
def trigger_local_calendar_sync():

    import subprocess

    try:

        script_path = Path(__file__).parent.parent / 'calendar_sync.py'
        if not script_path.exists():
            return jsonify({'success': False, 'error': 'Sync-Skript nicht gefunden'}), 404

        result = subprocess.run(
            ['python3', str(script_path), '--sync'],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode == 0:
            return jsonify({'success': True, 'message': 'Synchronisation abgeschlossen'})
        else:
            logging.error(f"Calendar sync failed: {result.stderr}")
            return jsonify({'success': False, 'error': 'Synchronisation fehlgeschlagen'}), 500

    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'error': 'Timeout bei der Synchronisation'}), 500
    except Exception as e:
        logging.error(f"Failed to sync local calendar: {e}")
        return jsonify({'success': False, 'error': 'Failed to sync calendar'}), 500

@app.route('/api/calendar/local/status', methods=['GET'])
def get_local_calendar_status():


    try:
        pid_file = DATA_DIR / 'calendar_sync.pid'

        daemon_running = False
        daemon_pid = None

        if pid_file.exists():
            try:
                with open(pid_file, 'r') as f:
                    daemon_pid = int(f.read().strip())

                import os
                os.kill(daemon_pid, 0)
                daemon_running = True
            except (ValueError, OSError, ProcessLookupError):
                daemon_running = False

        last_sync = None
        event_count = 0

        data = decrypt_file(SYNCED_CALENDAR_FILE)
        if data:
            last_sync = data.get('last_sync')
            event_count = data.get('event_count', 0)

        return jsonify({
            'success': True,
            'daemon_running': daemon_running,
            'daemon_pid': daemon_pid,
            'last_sync': last_sync,
            'event_count': event_count
        })

    except Exception as e:
        logging.error(f"Failed to get calendar sync status: {e}")
        return jsonify({'success': False, 'error': 'Failed to retrieve calendar status'}), 500

WEATHER_CACHE_FILE = DATA_DIR / 'weather_cache.json'

@app.route('/api/hub/weather', methods=['GET'])
def get_weather():

    import requests

    city = _bounded_str(request.args.get('city', 'Berlin'), 100)

    try:
        lat = float(request.args.get('lat', '52.52'))
        lon = float(request.args.get('lon', '13.41'))
    except (ValueError, TypeError):
        return jsonify({'success': False, 'error': 'Ungültige Koordinaten'}), 400

    if not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
        return jsonify({'success': False, 'error': 'Koordinaten außerhalb des gültigen Bereichs'}), 400

    try:

        response = requests.get(
            'https://api.open-meteo.com/v1/forecast',
            params={
                'latitude': lat,
                'longitude': lon,
                'current': 'temperature_2m,weather_code,wind_speed_10m',
                'daily': 'temperature_2m_max,temperature_2m_min,weather_code',
                'timezone': 'auto'
            },
            timeout=3
        )

        if response.ok:
            data = response.json()
            weather_data = {
                'current': data.get('current'),
                'daily': data.get('daily'),
                'location': {'lat': lat, 'lon': lon, 'city': city},
                'timestamp': datetime.now().isoformat(),
                'fetched_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            }

            encrypt_file(weather_data, WEATHER_CACHE_FILE)

            return jsonify({
                'success': True,
                'from_cache': False,
                **weather_data
            })
        else:
            raise Exception('Weather API error')

    except Exception as e:

        if WEATHER_CACHE_FILE.exists():
            try:
                cached_data = decrypt_file(WEATHER_CACHE_FILE)
                if cached_data:
                    return jsonify({
                        'success': True,
                        'from_cache': True,
                        'cached_at': cached_data.get('timestamp'),
                        **cached_data
                    })
            except Exception:
                pass

        logging.error(f"Weather API error: {e}")
        return jsonify({
            'success': False,
            'error': 'Wetterdaten konnten nicht abgerufen werden',
            'offline': True
        }), 503

BUNDESLAENDER = {
    'BW': 'Baden-Württemberg',
    'BY': 'Bayern',
    'BE': 'Berlin',
    'BB': 'Brandenburg',
    'HB': 'Bremen',
    'HH': 'Hamburg',
    'HE': 'Hessen',
    'MV': 'Mecklenburg-Vorpommern',
    'NI': 'Niedersachsen',
    'NW': 'Nordrhein-Westfalen',
    'RP': 'Rheinland-Pfalz',
    'SL': 'Saarland',
    'SN': 'Sachsen',
    'ST': 'Sachsen-Anhalt',
    'SH': 'Schleswig-Holstein',
    'TH': 'Thüringen'
}

@app.route('/api/hub/bundesland', methods=['GET'])
def get_bundesland():

    bundesland = db.get_bundesland_setting()
    settings = db.get_timetable_settings()
    return jsonify({
        'success': True,
        'bundesland': bundesland,
        'holidays_imported_until': settings.get('holidays_imported_until') if settings else None,
        'bundeslaender': BUNDESLAENDER
    })

def _import_holidays_for_bundesland(bundesland):
    try:
        current_year = datetime.now().year
        years_to_import = [current_year, current_year + 1, current_year + 2]

        db.clear_holidays()

        imported_count = 0
        errors = []

        for year in years_to_import:

            try:
                feiertage_url = f'https://feiertage-api.de/api/?jahr={year}&nur_land={bundesland}'
                logging.debug("Fetching Feiertage")
                response = requests.get(feiertage_url, timeout=10)
                logging.debug("Feiertage response received")
                if response.status_code == 200:
                    feiertage_data = response.json()
                    holidays = []
                    for name, info in feiertage_data.items():
                        holidays.append({
                            'date': info['datum'],
                            'name': name,
                            'type': 'feiertag',
                            'year': year
                        })
                    imported_count += db.import_holidays(holidays, bundesland)
                    logging.debug("Imported Feiertage for %d", year)
                else:
                    errors.append(f'Feiertage {year}: HTTP {response.status_code}')
            except Exception as e:
                logging.error(f"Feiertage error for {year}: {e}")
                errors.append(f'Feiertage {year}: Import fehlgeschlagen')

            schulferien_success = False
            try:
                schulferien_url = f'https://schulferien-api.de/api/v1/{year}/{bundesland}/'
                logging.debug("Fetching Schulferien from primary API")
                response = requests.get(schulferien_url, timeout=10)
                logging.debug("Primary Schulferien response received")
                if response.status_code == 200:
                    ferien_data = response.json()
                    holidays = []
                    for ferien in ferien_data:

                        name = ferien.get('name_cp') or ferien.get('name', '')
                        holidays.append({
                            'date': ferien['start'][:10],
                            'end_date': ferien['end'][:10],
                            'name': name,
                            'type': 'schulferien',
                            'year': year
                        })
                    imported_count += db.import_holidays(holidays, bundesland)
                    logging.debug("Imported Schulferien for %d from primary API", year)
                    schulferien_success = True
            except Exception as e:
                logging.warning("Primary Schulferien API error for %d: %s", year, e)

            if not schulferien_success:
                try:
                    ferien_url = f'https://ferien-api.de/api/v1/holidays/{bundesland}/{year}'
                    logging.debug("Fetching Schulferien from fallback API")
                    response = requests.get(ferien_url, timeout=10)
                    logging.debug("Fallback Schulferien response received")
                    if response.status_code == 200:
                        ferien_data = response.json()
                        holidays = []
                        for ferien in ferien_data:
                            holidays.append({
                                'date': ferien['start'][:10],
                                'end_date': ferien['end'][:10],
                                'name': ferien['name'],
                                'type': 'schulferien',
                                'year': year
                            })
                        imported_count += db.import_holidays(holidays, bundesland)
                        logging.debug("Imported Schulferien for %d from fallback API", year)
                    else:
                        errors.append(f'Schulferien {year}: HTTP {response.status_code}')
                except Exception as e:
                    logging.error(f"Fallback Schulferien error for {year}: {e}")
                    errors.append(f'Schulferien {year}: Import fehlgeschlagen')

        db.save_bundesland_setting(bundesland, holidays_imported_until=years_to_import[-1])
        logging.debug("Saved Bundesland setting, imported %d holidays", imported_count)

        return jsonify({
            'success': True,
            'bundesland': bundesland,
            'bundesland_name': BUNDESLAENDER[bundesland],
            'imported_count': imported_count,
            'years': years_to_import,
            'errors': errors if errors else None
        })
    except Exception as e:
        logging.error(f"Failed to import holidays for Bundesland: {e}")
        return jsonify({'success': False, 'error': 'Failed to import holidays'}), 500


@app.route('/api/hub/bundesland', methods=['POST'])
def save_bundesland():
    data = request.get_json(silent=True)
    if not data or 'bundesland' not in data:
        return jsonify({'success': False, 'error': 'Bundesland is required'}), 400
    bundesland = data['bundesland']
    if bundesland not in BUNDESLAENDER:
        return jsonify({'success': False, 'error': 'Invalid Bundesland code'}), 400
    return _import_holidays_for_bundesland(bundesland)

@app.route('/api/hub/holidays', methods=['GET'])
def get_hub_holidays():

    year = request.args.get('year', type=int)
    holiday_type = request.args.get('type')
    start_date = request.args.get('start')
    end_date = request.args.get('end')

    bundesland = db.get_bundesland_setting()

    if start_date and end_date:
        holidays = db.get_holidays_for_date_range(start_date, end_date, bundesland)
    else:
        holidays = db.get_holidays(bundesland=bundesland, year=year, holiday_type=holiday_type)

    return jsonify({
        'success': True,
        'bundesland': bundesland,
        'holidays': holidays
    })

@app.route('/api/hub/holidays/refresh', methods=['POST'])
def refresh_holidays():

    bundesland = db.get_bundesland_setting()
    if not bundesland:
        return jsonify({'success': False, 'error': 'No Bundesland set'}), 400

    return _import_holidays_for_bundesland(bundesland)

@app.route('/api/calendar/holidays', methods=['GET'])
def get_calendar_holidays():

    try:
        bundesland = db.get_bundesland_setting()
        if not bundesland:
            return jsonify({
                'success': True,
                'holidays': [],
                'needs_bundesland': True
            })

        holidays = db.get_holidays(bundesland=bundesland)

        formatted_holidays = []
        for h in holidays:
            formatted_holidays.append({
                'name': h['name'],
                'start': h['date'],
                'end': h.get('end_date') or h['date'],
                'type': h['type']
            })

        return jsonify({
            'success': True,
            'bundesland': bundesland,
            'bundesland_name': BUNDESLAENDER.get(bundesland, bundesland),
            'holidays': formatted_holidays
        })
    except Exception as e:
        logging.error(f"Failed to retrieve holidays: {e}")
        return jsonify({'success': False, 'error': 'Failed to retrieve holidays'}), 500

@app.route('/api/pomodoro/session', methods=['POST'])
def save_pomodoro_session():

    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': 'No data provided'}), 400

    session_id = db.create_pomodoro_session(
        subject_id=data.get('subject_id'),
        duration=data.get('duration', 25),
        session_type=data.get('session_type', 'work')
    )
    return jsonify({'success': True, 'session_id': session_id})

@app.route('/api/pomodoro/stats', methods=['GET'])
def get_pomodoro_stats():

    range_type = request.args.get('range', 'week')
    stats = db.get_pomodoro_stats(range_type)
    return jsonify(stats)

@app.route('/api/pomodoro/sessions', methods=['GET'])
def get_pomodoro_sessions():

    limit = min(max(request.args.get('limit', 50, type=int), 1), 200)
    sessions = db.get_pomodoro_sessions(limit=limit)
    return jsonify({'sessions': sessions})

# ---- Analytics API ----

@app.route('/api/hub/analytics', methods=['GET'])
def get_analytics():
    from . import analytics_service as analytics

    range_days = min(max(request.args.get('range', 30, type=int), 7), 3650)
    section = request.args.get('section', 'all')

    subjects = load_school_subjects()
    grades = load_school_grades()

    result = {}
    try:
        if section in ('all', 'productivity'):
            result['productivity'] = analytics.get_productivity_trends(range_days)
            result['task_stats'] = analytics.get_task_stats(range_days)
        if section in ('all', 'grades'):
            settings = db.get_timetable_settings()
            grade_system = settings.get('grade_system', 'points') if settings else 'points'
            grade_data = analytics.get_grade_trends(subjects, grades)
            grade_data['grade_system'] = grade_system
            result['grades'] = grade_data
        if section in ('all', 'health'):
            result['correlations'] = analytics.get_health_correlations(range_days)
        if section in ('all', 'training'):
            result['training'] = analytics.get_training_trends(range_days)
        if section in ('all', 'study'):
            result['study'] = analytics.get_study_analytics(range_days, subjects)
        if section in ('all', 'digest'):
            result['digest'] = analytics.get_digest(range_days)
        if section in ('all', 'fun_facts'):
            result['fun_facts'] = analytics.get_fun_facts(range_days)
    except Exception as e:
        logging.error(f'Analytics error: {type(e).__name__}')
        return jsonify({'error': 'Analytics computation failed'}), 500

    return jsonify(result)

# ---- AI Assistant API ----

def _load_school_data_for_assistant():
    return (load_school_subjects(), load_school_homework(),
            load_school_exams(), load_school_tests(), load_school_grades())

def _load_school_item(item_type):
    if item_type == 'homework':
        return load_school_homework()
    if item_type == 'exams':
        return load_school_exams()
    if item_type == 'tests':
        return load_school_tests()
    return []

def _save_school_item(item_type, data):
    if item_type == 'homework':
        save_school_homework(data)
    elif item_type == 'exams':
        save_school_exams(data)
    elif item_type == 'tests':
        save_school_tests(data)

@app.route('/api/hub/assistant/status', methods=['GET'])
def assistant_status():
    from . import assistant_service as ai
    return jsonify(ai.get_status())

@app.route('/api/hub/assistant/models', methods=['GET'])
def assistant_models():
    from . import assistant_service as ai
    models = ai.get_ollama_models()
    return jsonify({'models': [{'name': m} for m in models]})

def _llm_history_for_context():
    from . import assistant_service as ai

    full = load_assistant_history()
    trimmed = full[-ASSISTANT_LLM_CONTEXT_TURNS:]
    return [
        {'role': m['role'], 'content': ai.extract_ollama_actions(m['content'])[0] if m['role'] == 'assistant' else m['content']}
        for m in trimmed if m.get('role') in ('user', 'assistant')
    ]


@app.route('/api/hub/assistant/history', methods=['GET', 'DELETE'])
def assistant_history_route():
    if request.method == 'DELETE':
        save_assistant_history([])
        return jsonify({'success': True})
    return jsonify({'history': load_assistant_history()})


MAX_MODEL_ACTIONS = 5


def _run_model_actions(ai, actions, message, researched):
    results = []
    for index, action in enumerate(actions):
        refusal = ai.model_action_refusal(action, message, researched)
        if index >= MAX_MODEL_ACTIONS:
            refusal = 'Aktion übersprungen: zu viele Aktionen in einer Antwort'
        if refusal:
            results.append({'success': False, 'message': refusal})
            continue
        try:
            results.append(ai.execute_action(action, _load_school_item, _save_school_item))
        except Exception as e:
            logging.error(f'Assistant action error: {type(e).__name__}')
            results.append({'success': False, 'message': 'Aktion fehlgeschlagen'})
    return results


@app.route('/api/hub/assistant/chat', methods=['POST'])
def assistant_chat():
    from . import assistant_service as ai

    data = request.get_json(silent=True)
    message = data.get('message') if data else None
    if not isinstance(message, str) or not message.strip():
        return jsonify({'error': 'Message required'}), 400

    message = message.strip()[:10000]
    history = _llm_history_for_context()

    context = ai.build_context(lambda: _load_school_data_for_assistant(), message)
    from . import research_service
    research_block = research_service.research_for_message(message)
    if research_block:
        context = f'{context}\n\n{research_block}'
    system_prompt = ai.build_system_prompt(context)
    backend = ai.get_active_backend()

    actions_executed = []

    try:
        if backend == 'ollama':
            config = ai.load_config()
            model = data.get('model', config.get('ollama_model', 'llama3.2'))
            response_text = ai.chat_ollama(message, system_prompt, model, history)
            response_text, ollama_actions = ai.extract_ollama_actions(response_text)
            actions_executed = _run_model_actions(ai, ollama_actions, message, bool(research_block))

        elif backend == 'claude':
            response_text, tool_uses = ai.chat_claude(
                message, system_prompt, history, tools=ai.TOOL_SCHEMAS
            )
            actions_executed = _run_model_actions(ai, tool_uses, message, bool(research_block))

        elif backend == 'local':
            offline_result = ai.offline_response(message, lambda: _load_school_data_for_assistant())
            is_data_query = ai.is_data_query(message)

            if is_data_query:
                response_text = offline_result
            else:
                response_text = ai.chat_local(message, system_prompt, history)
                if response_text:
                    response_text, local_actions = ai.extract_ollama_actions(response_text)
                    actions_executed = _run_model_actions(ai, local_actions, message, bool(research_block))
                else:
                    response_text = offline_result

        else:
            response_text = ai.offline_response(message, lambda: _load_school_data_for_assistant())

    except Exception as e:
        logging.error(f'Assistant chat error: {type(e).__name__}')
        response_text = ai.offline_response(message, lambda: _load_school_data_for_assistant())
        backend = 'offline'

    append_assistant_history('user', message)
    if response_text and response_text.strip():
        append_assistant_history('assistant', ai.extract_ollama_actions(response_text)[0])

    return jsonify({
        'response': response_text,
        'backend': backend,
        'actions_executed': actions_executed,
    })

@app.route('/api/hub/assistant/stream', methods=['POST'])
def assistant_stream():
    from . import assistant_service as ai
    from flask import Response

    data = request.get_json(silent=True)
    message = data.get('message') if data else None
    if not isinstance(message, str) or not message.strip():
        return jsonify({'error': 'Message required'}), 400

    message = message.strip()[:10000]
    history = _llm_history_for_context()

    context = ai.build_context(lambda: _load_school_data_for_assistant(), message)
    from . import research_service
    research_block = research_service.research_for_message(message)
    if research_block:
        context = f'{context}\n\n{research_block}'
    system_prompt = ai.build_system_prompt(context)
    backend = ai.get_active_backend()

    def generate():
        buffer_parts = []
        from_model = False
        try:
            if backend == 'ollama':
                config = ai.load_config()
                model = data.get('model', config.get('ollama_model', 'llama3.2'))
                from_model = True
                for chunk in ai.stream_ollama(message, system_prompt, model, history):
                    buffer_parts.append(chunk)
                    yield f"data: {json.dumps({'token': chunk})}\n\n"
            elif backend == 'claude':
                from_model = True
                for chunk in ai.stream_claude(message, system_prompt, history):
                    buffer_parts.append(chunk)
                    yield f"data: {json.dumps({'token': chunk})}\n\n"
            elif backend == 'local':
                if ai.is_data_query(message):
                    response = ai.offline_response(message, lambda: _load_school_data_for_assistant())
                    buffer_parts.append(response)
                    yield f"data: {json.dumps({'token': response})}\n\n"
                else:
                    from_model = True
                    for chunk in ai.stream_local(message, system_prompt, history):
                        buffer_parts.append(chunk)
                        yield f"data: {json.dumps({'token': chunk})}\n\n"
            else:
                response = ai.offline_response(message, lambda: _load_school_data_for_assistant())
                buffer_parts.append(response)
                yield f"data: {json.dumps({'token': response})}\n\n"
        except Exception as e:
            logging.error(f'Stream error: {type(e).__name__}')
            fallback = ai.offline_response(message, lambda: _load_school_data_for_assistant())
            buffer_parts = [fallback]
            from_model = False
            yield f"data: {json.dumps({'token': fallback})}\n\n"

        raw = ''.join(buffer_parts)
        cleaned, actions = ai.extract_ollama_actions(raw)
        actions_executed = _run_model_actions(ai, actions if from_model else [], message, bool(research_block))

        append_assistant_history('user', message)
        if cleaned.strip():
            append_assistant_history('assistant', cleaned)

        yield f"data: {json.dumps({'done': True, 'backend': backend, 'cleaned': cleaned, 'actions_executed': actions_executed})}\n\n"

    return Response(generate(), mimetype='text/event-stream',
                    headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})

@app.route('/api/hub/assistant/config', methods=['GET', 'POST'])
def assistant_config():
    from . import assistant_service as ai

    if request.method == 'GET':
        config = ai.load_config()
        key = config.get('claude_api_key', '')
        masked = ''
        if key:
            masked = key[:7] + '...' + key[-4:] if len(key) > 15 else '***'
        return jsonify({
            'claude_api_key_set': bool(key),
            'claude_api_key_masked': masked,
            'preferred_backend': config.get('preferred_backend', 'auto'),
            'ollama_model': config.get('ollama_model', 'llama3.2:1b'),
            'claude_model': config.get('claude_model', 'claude-sonnet-4-20250514'),
        })

    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data'}), 400

    config = ai.load_config()
    if 'claude_api_key' in data:
        config['claude_api_key'] = data['claude_api_key']
    if 'preferred_backend' in data:
        if data['preferred_backend'] in ('auto', 'ollama', 'local', 'claude', 'offline'):
            config['preferred_backend'] = data['preferred_backend']
    if 'ollama_model' in data:
        config['ollama_model'] = data['ollama_model']
    if 'claude_model' in data:
        config['claude_model'] = data['claude_model']

    ai.save_config(config)
    return jsonify({'success': True})

@app.route('/api/deadlines', methods=['GET'])
def get_all_deadlines():

    days = min(max(request.args.get('days', 14, type=int), 1), 365)
    deadlines = []
    today = datetime.now().date()

    homework = load_school_homework()
    for hw in homework:
        if hw.get('completed'):
            continue
        try:
            due_date = datetime.strptime(hw['due_date'], '%Y-%m-%d').date()
            days_until = (due_date - today).days
            if 0 <= days_until <= days:
                deadlines.append({
                    'id': hw['id'],
                    'type': 'homework',
                    'title': hw['title'],
                    'subject_id': hw.get('subject_id'),
                    'due_date': hw['due_date'],
                    'days_until': days_until,
                    'urgency': 'urgent' if days_until == 0 else 'warning' if days_until <= 1 else 'normal'
                })
        except (ValueError, KeyError):
            continue

    tests = load_school_tests()
    for test in tests:
        try:
            test_date = datetime.strptime(test['date'], '%Y-%m-%d').date()
            days_until = (test_date - today).days
            if 0 <= days_until <= days:
                deadlines.append({
                    'id': test['id'],
                    'type': 'test',
                    'title': test.get('title', 'Test'),
                    'subject_id': test.get('subject_id'),
                    'due_date': test['date'],
                    'days_until': days_until,
                    'urgency': 'urgent' if days_until == 0 else 'warning' if days_until <= 1 else 'normal'
                })
        except (ValueError, KeyError):
            continue

    exams = load_school_exams()
    for exam in exams:
        try:
            exam_date = datetime.strptime(exam['date'], '%Y-%m-%d').date()
            days_until = (exam_date - today).days
            if 0 <= days_until <= days:
                deadlines.append({
                    'id': exam['id'],
                    'type': 'exam',
                    'title': exam.get('title', 'Klausur'),
                    'subject_id': exam.get('subject_id'),
                    'due_date': exam['date'],
                    'days_until': days_until,
                    'urgency': 'urgent' if days_until == 0 else 'warning' if days_until <= 2 else 'normal'
                })
        except (ValueError, KeyError):
            continue

    deadlines.sort(key=lambda x: x['days_until'])

    return jsonify({
        'success': True,
        'deadlines': deadlines,
        'count': len(deadlines)
    })

if __name__ == '__main__':
    import socket

    def get_local_ip():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return None

    host = os.environ.get('HUB_HOST', '127.0.0.1')
    port = int(env('PORT', 5050))
    local_ip = get_local_ip()

    logging.info("%s - Personal Dashboard", brand.NAME)
    logging.info("Desktop: http://127.0.0.1:%d", port)
    if host == '0.0.0.0' and local_ip:
        logging.info("Mobile: http://%s:%d", local_ip, port)
    logging.info("Tipp: Auf dem Handy die Mobile-URL eingeben und 'Zum Home-Bildschirm' hinzufugen!")

    show_login_url = sys.stdout.isatty() and not DESKTOP_TOKEN
    if show_login_url:
        print("\nZum Anmelden im Browser einmal diese Adresse oeffnen:")
        print(f"   http://127.0.0.1:{port}/hub?token={API_TOKEN}")
        if host == '0.0.0.0' and local_ip:
            print(f"   http://{local_ip}:{port}/hub?token={API_TOKEN}")
        print("Danach haelt die Anmeldung in diesem Browser.\n")
    else:
        logging.info("Anmeldeadresse wird nur an einem Terminal angezeigt.")
        logging.info("Token liegt verschluesselt in data/.api_token")

    unsafe = (os.environ.get('HUB_ALLOW_UNSAFE_WERKZEUG') == '1'
              or os.environ.get('FLASK_ENV') == 'development')
    socketio.run(app, host=host, port=port, debug=False, allow_unsafe_werkzeug=unsafe)
