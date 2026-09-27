# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import json
import sqlite3
import os
import logging
from datetime import datetime
from typing import List, Optional, Dict, Any

logger = logging.getLogger(__name__)

DATABASE_URL = os.environ.get('DATABASE_URL')

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.environ.get("HUB_DATA_DIR") or os.path.join(PROJECT_ROOT, "data")
DATABASE_PATH = os.path.join(DATA_DIR, "hub.db")


def _adopt_previous_database():
    previous = os.path.join(DATA_DIR, "nexus.db")
    if os.path.exists(DATABASE_PATH) or not os.path.exists(previous):
        return
    for suffix in ("", "-wal", "-shm", "-journal"):
        if os.path.exists(previous + suffix):
            os.replace(previous + suffix, DATABASE_PATH + suffix)


_adopt_previous_database()

_use_postgres = False
if DATABASE_URL:
    try:
        import psycopg2
        import psycopg2.extras
        _use_postgres = True
    except ImportError:
        print("Warning: DATABASE_URL set but psycopg2 not installed. Using SQLite.")
        _use_postgres = False

def get_connection():

    if _use_postgres:

        conn = psycopg2.connect(DATABASE_URL)
        return conn
    else:

        db_dir = os.path.dirname(DATABASE_PATH)
        os.makedirs(db_dir, exist_ok=True)
        try:
            os.chmod(db_dir, 0o700)
        except OSError:
            pass
        fresh = not os.path.exists(DATABASE_PATH)
        conn = sqlite3.connect(DATABASE_PATH)
        conn.row_factory = sqlite3.Row
        if fresh:
            try:
                os.chmod(DATABASE_PATH, 0o600)
            except OSError:
                pass
        return conn

def _execute(cursor, query, params=None):

    if _use_postgres:

        query = query.replace('?', '%s')
    cursor.execute(query, params or ())
    return cursor

def _fetchone_dict(cursor):

    row = cursor.fetchone()
    if row is None:
        return None
    if _use_postgres:
        columns = [desc[0] for desc in cursor.description]
        return dict(zip(columns, row))
    return dict(row)

def _fetchall_dict(cursor):

    rows = cursor.fetchall()
    if _use_postgres:
        columns = [desc[0] for desc in cursor.description]
        return [dict(zip(columns, row)) for row in rows]
    return [dict(row) for row in rows]

RETIRED_TABLES = ('hub_projects', 'hub_knowledge', 'hub_drawings')

def _drop_retired_tables(cursor):
    for table in RETIRED_TABLES:
        cursor.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,))
        if cursor.fetchone() is None:
            continue
        cursor.execute(f'SELECT COUNT(*) FROM {table}')
        rows = cursor.fetchone()[0]
        if rows:
            logger.warning('Keeping retired table %s because it is not empty (rows: %d)', table, rows)
        else:
            cursor.execute(f'DROP TABLE {table}')

def init_db():
    conn = get_connection()
    cursor = conn.cursor()

    pk = 'SERIAL PRIMARY KEY' if _use_postgres else 'INTEGER PRIMARY KEY AUTOINCREMENT'

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_tasks (
            id {pk},
            title TEXT NOT NULL,
            description TEXT,
            due_date TEXT,
            due_time TEXT,
            priority TEXT DEFAULT 'medium',
            category TEXT,
            completed INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP,
            repeat_type TEXT DEFAULT 'none',
            repeat_days TEXT,
            repeat_end_date TEXT,
            parent_task_id INTEGER
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_reviews (
            id {pk},
            type TEXT DEFAULT 'daily',
            date TEXT NOT NULL,
            data TEXT,
            energy INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_training_sessions (
            id {pk},
            type TEXT NOT NULL,
            date TEXT NOT NULL,
            duration INTEGER,
            notes TEXT,
            calories INTEGER,
            exercises TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_training_health (
            id {pk},
            date TEXT NOT NULL,
            sleep REAL,
            energy INTEGER,
            stress INTEGER,
            recovery INTEGER,
            weight REAL,
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_training_goals (
            id {pk},
            title TEXT NOT NULL,
            target REAL,
            current REAL DEFAULT 0,
            unit TEXT,
            deadline TEXT,
            completed INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_training_schedule_settings (
            id {pk},
            schedule_mode TEXT DEFAULT 'regular',
            auto_detect_holiday INTEGER DEFAULT 1,
            setup_completed INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_training_schedule_entries (
            id {pk},
            day INTEGER NOT NULL,
            schedule_type TEXT DEFAULT 'regular',
            training_type TEXT NOT NULL,
            title TEXT NOT NULL,
            time TEXT,
            duration INTEGER,
            location TEXT,
            muscle_groups TEXT,
            notes TEXT,
            icon TEXT,
            color TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_training_schedule_day_type
        ON hub_training_schedule_entries(day, schedule_type)
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_timetable_settings (
            id {pk},
            has_ab_weeks INTEGER DEFAULT 1,
            block_count INTEGER DEFAULT 4,
            reference_date TEXT,
            setup_completed INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    try:
        cursor.execute('ALTER TABLE hub_timetable_settings ADD COLUMN grade_system TEXT DEFAULT \'points\'')
        conn.commit()
    except Exception:
        pass

    try:
        cursor.execute("ALTER TABLE hub_timetable_settings ADD COLUMN class_level INTEGER DEFAULT 10")
        conn.commit()
    except Exception:
        pass

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_timetable_entries (
            id {pk},
            day INTEGER NOT NULL,
            block INTEGER NOT NULL,
            week TEXT DEFAULT 'both',
            subject TEXT NOT NULL,
            subject_type TEXT DEFAULT 'GK',
            room TEXT,
            teacher TEXT,
            color TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_timetable_day_block
        ON hub_timetable_entries(day, block, week)
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_timetable_periods (
            id {pk},
            period_number INTEGER NOT NULL UNIQUE,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS pomodoro_sessions (
            id {pk},
            subject_id TEXT,
            duration INTEGER NOT NULL DEFAULT 25,
            session_type TEXT DEFAULT 'work',
            completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_pomodoro_completed_at
        ON pomodoro_sessions(completed_at)
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_holidays (
            id {pk},
            date TEXT NOT NULL,
            end_date TEXT,
            name TEXT NOT NULL,
            type TEXT DEFAULT 'feiertag',
            bundesland TEXT NOT NULL,
            year INTEGER NOT NULL,
            user_id TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_holidays_bundesland_year
        ON hub_holidays(bundesland, year)
    ''')

    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_holidays_date
        ON hub_holidays(date)
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_bookmarks (
            id {pk},
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            category TEXT DEFAULT 'Other',
            favicon TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_user_tickets (
            id {pk},
            user_id TEXT,
            ticket_type TEXT NOT NULL,
            ticket_name TEXT NOT NULL,
            zone_coverage TEXT NOT NULL,
            valid_from TEXT,
            valid_until TEXT,
            auto_renews INTEGER DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS hub_monitored_routes (
            id {pk},
            user_id TEXT,
            route_data TEXT NOT NULL,
            from_name TEXT,
            to_name TEXT,
            departure_time TEXT NOT NULL,
            status TEXT DEFAULT 'active',
            last_check TEXT,
            current_delays TEXT,
            notifications_sent TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    if not _use_postgres:
        repeat_columns = [
            ('repeat_type', "TEXT DEFAULT 'none'"),
            ('repeat_days', 'TEXT'),
            ('repeat_end_date', 'TEXT'),
            ('parent_task_id', 'INTEGER'),
            ('subject', 'TEXT'),
            ('minutes', 'INTEGER'),
            ('deadline_ref', 'TEXT'),
            ('someday', 'INTEGER DEFAULT 0'),
            ('source', 'TEXT')
        ]
        for col_name, col_def in repeat_columns:
            try:
                cursor.execute(f'ALTER TABLE hub_tasks ADD COLUMN {col_name} {col_def}')
            except sqlite3.OperationalError:
                pass

        try:
            cursor.execute('ALTER TABLE hub_timetable_settings ADD COLUMN bundesland TEXT')
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute('ALTER TABLE hub_timetable_settings ADD COLUMN holidays_imported_until INTEGER')
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute('ALTER TABLE hub_timetable_settings ADD COLUMN birthday TEXT')
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute('ALTER TABLE hub_timetable_settings ADD COLUMN theme TEXT DEFAULT \'dark\'')
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute('ALTER TABLE hub_timetable_settings ADD COLUMN location_json TEXT')
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute("ALTER TABLE hub_timetable_settings ADD COLUMN theme_mode TEXT DEFAULT 'manual'")
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute('ALTER TABLE hub_timetable_settings ADD COLUMN theme_schedule_json TEXT')
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute('ALTER TABLE hub_timetable_settings ADD COLUMN tour_state TEXT')
        except sqlite3.OperationalError:
            pass

        hub_tables_needing_user_id = [
            'hub_tasks',
            'hub_reviews',
            'hub_training_sessions',
            'hub_training_health',
            'hub_training_goals',
            'hub_training_schedule_settings',
            'hub_training_schedule_entries',
            'hub_timetable_settings',
            'hub_timetable_entries'
        ]
        for table in hub_tables_needing_user_id:
            try:
                cursor.execute(f'ALTER TABLE {table} ADD COLUMN user_id TEXT')
            except sqlite3.OperationalError:
                pass

        _drop_retired_tables(cursor)

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS ui_store (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    ''')

    conn.commit()
    conn.close()

    if not _use_postgres and os.path.exists(DATABASE_PATH):
        os.chmod(DATABASE_PATH, 0o600)

def get_hub_tasks(filter_type: str = 'all', user_id: str = None) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    user_filter = 'AND user_id = ?' if user_id else ''
    user_param = (user_id,) if user_id else ()

    if filter_type == 'today':
        today = datetime.now().strftime('%Y-%m-%d')
        cursor.execute(f'''
            SELECT * FROM hub_tasks
            WHERE due_date = ? AND completed = 0 {user_filter}
            ORDER BY due_time ASC, priority DESC, created_at DESC
        ''', (today,) + user_param)
    elif filter_type == 'upcoming':
        today = datetime.now().strftime('%Y-%m-%d')
        cursor.execute(f'''
            SELECT * FROM hub_tasks
            WHERE due_date > ? AND completed = 0 {user_filter}
            ORDER BY due_date ASC, due_time ASC, priority DESC
        ''', (today,) + user_param)
    elif filter_type == 'overdue':
        today = datetime.now().strftime('%Y-%m-%d')
        cursor.execute(f'''
            SELECT * FROM hub_tasks
            WHERE due_date < ? AND completed = 0 {user_filter}
            ORDER BY due_date ASC, priority DESC
        ''', (today,) + user_param)
    elif filter_type == 'completed':
        cursor.execute(f'''
            SELECT * FROM hub_tasks
            WHERE completed = 1 {user_filter}
            ORDER BY completed_at DESC
        ''', user_param)
    else:
        cursor.execute(f'''
            SELECT * FROM hub_tasks
            WHERE 1=1 {user_filter}
            ORDER BY completed ASC, due_date ASC, due_time ASC, priority DESC, created_at DESC
        ''', user_param)

    tasks = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return tasks

def get_hub_task(task_id: int) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_tasks WHERE id = ?', (task_id,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def create_hub_task(title: str, description: str = None, due_date: str = None,
                    due_time: str = None, priority: str = 'medium', category: str = None,
                    user_id: str = None, repeat_type: str = 'none', repeat_days: str = None,
                    repeat_end_date: str = None, parent_task_id: int = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO hub_tasks (title, description, due_date, due_time, priority, category, user_id,
                              repeat_type, repeat_days, repeat_end_date, parent_task_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (title, description, due_date, due_time, priority, category, user_id,
          repeat_type, repeat_days, repeat_end_date, parent_task_id))
    task_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return task_id

def update_hub_task(task_id: int, title: str = None, description: str = None,
                    due_date: str = None, due_time: str = None, priority: str = None,
                    category: str = None, repeat_type: str = None, repeat_days: str = None,
                    repeat_end_date: str = None) -> bool:

    conn = get_connection()
    cursor = conn.cursor()

    updates = []
    params = []

    if title is not None:
        updates.append('title = ?')
        params.append(title)
    if description is not None:
        updates.append('description = ?')
        params.append(description)
    if due_date is not None:
        updates.append('due_date = ?')
        params.append(due_date)
    if due_time is not None:
        updates.append('due_time = ?')
        params.append(due_time)
    if priority is not None:
        updates.append('priority = ?')
        params.append(priority)
    if category is not None:
        updates.append('category = ?')
        params.append(category)
    if repeat_type is not None:
        updates.append('repeat_type = ?')
        params.append(repeat_type)
    if repeat_days is not None:
        updates.append('repeat_days = ?')
        params.append(repeat_days)
    if repeat_end_date is not None:
        updates.append('repeat_end_date = ?')
        params.append(repeat_end_date if repeat_end_date != '' else None)

    if not updates:
        conn.close()
        return False

    updates.append('updated_at = CURRENT_TIMESTAMP')
    params.append(task_id)

    cursor.execute(f'''
        UPDATE hub_tasks SET {', '.join(updates)} WHERE id = ?
    ''', params)
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def toggle_hub_task(task_id: int, stop_recurrence: bool = False) -> dict:


    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute('SELECT * FROM hub_tasks WHERE id = ?', (task_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        return {'success': False}

    task = dict(row)
    new_status = 0 if task['completed'] else 1
    completed_at = datetime.now().isoformat() if new_status else None

    cursor.execute('''
        UPDATE hub_tasks
        SET completed = ?, completed_at = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    ''', (new_status, completed_at, task_id))

    if stop_recurrence and new_status == 1:
        cursor.execute('''
            UPDATE hub_tasks
            SET repeat_type = 'none', repeat_days = NULL, repeat_end_date = NULL,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ''', (task_id,))

    next_task_id = None

    if new_status == 1 and not stop_recurrence and task.get('repeat_type') and task['repeat_type'] != 'none':
        next_due_date = calculate_next_due_date(
            task.get('due_date'),
            task['repeat_type'],
            task.get('repeat_days')
        )

        should_create = True
        if task.get('repeat_end_date') and next_due_date:
            if next_due_date > task['repeat_end_date']:
                should_create = False

        if should_create and next_due_date:
            cursor.execute('''
                INSERT INTO hub_tasks (title, description, due_date, due_time, priority, category, user_id,
                                      repeat_type, repeat_days, repeat_end_date, parent_task_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (task['title'], task.get('description'), next_due_date, task.get('due_time'),
                  task.get('priority', 'medium'), task.get('category'), task.get('user_id'),
                  task['repeat_type'], task.get('repeat_days'), task.get('repeat_end_date'),
                  task.get('parent_task_id') or task_id))
            next_task_id = cursor.lastrowid

    if new_status == 1:
        cursor.execute('''
            SELECT id FROM hub_tasks
            WHERE completed = 1
            ORDER BY completed_at DESC
            LIMIT -1 OFFSET 3
        ''')
        old_completed = cursor.fetchall()
        if old_completed:
            ids_to_delete = [row['id'] for row in old_completed]
            cursor.execute(
                f"DELETE FROM hub_tasks WHERE id IN ({','.join('?' * len(ids_to_delete))})",
                ids_to_delete
            )

    conn.commit()
    conn.close()
    return {'success': True, 'next_task_id': next_task_id}

def calculate_next_due_date(current_due: str, repeat_type: str, repeat_days: str = None) -> str:

    from datetime import timedelta
    import json

    if not current_due:

        current_date = datetime.now().date()
    else:
        current_date = datetime.strptime(current_due[:10], '%Y-%m-%d').date()

    if repeat_type == 'daily':
        next_date = current_date + timedelta(days=1)
    elif repeat_type == 'weekly':
        next_date = current_date + timedelta(weeks=1)
    elif repeat_type == 'monthly':

        month = current_date.month + 1
        year = current_date.year
        if month > 12:
            month = 1
            year += 1
        day = min(current_date.day, 28)
        next_date = current_date.replace(year=year, month=month, day=day)
    elif repeat_type == 'yearly':
        try:
            next_date = current_date.replace(year=current_date.year + 1)
        except ValueError:
            next_date = current_date.replace(year=current_date.year + 1, day=28)
    elif repeat_type == 'custom' and repeat_days:

        try:
            days = json.loads(repeat_days) if isinstance(repeat_days, str) else repeat_days
            if days:

                for i in range(1, 8):
                    check_date = current_date + timedelta(days=i)

                    js_weekday = (check_date.weekday() + 1) % 7
                    if js_weekday in days:
                        next_date = check_date
                        break
                else:
                    next_date = current_date + timedelta(weeks=1)
            else:
                next_date = current_date + timedelta(weeks=1)
        except (json.JSONDecodeError, TypeError):
            next_date = current_date + timedelta(weeks=1)
    else:
        return None

    return next_date.isoformat()

def delete_hub_task(task_id: int) -> bool:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_tasks WHERE id = ?', (task_id,))
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def delete_hub_task_all_occurrences(task_id: int) -> int:

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute('SELECT id, parent_task_id FROM hub_tasks WHERE id = ?', (task_id,))
    task = cursor.fetchone()
    if not task:
        conn.close()
        return 0

    root_id = task['parent_task_id'] if task['parent_task_id'] else task_id

    cursor.execute('DELETE FROM hub_tasks WHERE parent_task_id = ? OR id = ?', (root_id, root_id))
    affected = cursor.rowcount

    cursor.execute('DELETE FROM hub_tasks WHERE parent_task_id = ?', (task_id,))
    affected += cursor.rowcount

    conn.commit()
    conn.close()
    return affected

def skip_hub_task_occurrence(task_id: int) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute('SELECT * FROM hub_tasks WHERE id = ?', (task_id,))
    task = _fetchone_dict(cursor)
    if not task:
        conn.close()
        return None

    repeat_type = task.get('repeat_type', 'none')
    if repeat_type == 'none':

        cursor.execute('DELETE FROM hub_tasks WHERE id = ?', (task_id,))
        conn.commit()
        conn.close()
        return {'deleted': True, 'next_task': None}

    next_due = calculate_next_due_date(task.get('due_date'), repeat_type, task.get('repeat_days'))
    if not next_due:

        cursor.execute('DELETE FROM hub_tasks WHERE id = ?', (task_id,))
        conn.commit()
        conn.close()
        return {'deleted': True, 'next_task': None}

    parent_id = task.get('parent_task_id') or task_id
    cursor.execute('''
        INSERT INTO hub_tasks (title, description, due_date, due_time, priority, category,
                              repeat_type, repeat_days, repeat_end_date, parent_task_id, user_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        task['title'],
        task.get('description'),
        next_due,
        task.get('due_time'),
        task.get('priority', 'medium'),
        task.get('category'),
        task['repeat_type'],
        task.get('repeat_days'),
        task.get('repeat_end_date'),
        parent_id,
        task.get('user_id')
    ))
    next_task_id = cursor.lastrowid

    cursor.execute('DELETE FROM hub_tasks WHERE id = ?', (task_id,))

    conn.commit()

    cursor.execute('SELECT * FROM hub_tasks WHERE id = ?', (next_task_id,))
    next_task = _fetchone_dict(cursor)
    conn.close()

    return {'deleted': True, 'next_task': next_task}

def get_hub_reviews(review_type: str = None, limit: int = 50) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    if review_type:
        cursor.execute('''
            SELECT * FROM hub_reviews WHERE type = ?
            ORDER BY date DESC LIMIT ?
        ''', (review_type, limit))
    else:
        cursor.execute('''
            SELECT * FROM hub_reviews
            ORDER BY date DESC LIMIT ?
        ''', (limit,))

    reviews = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return reviews

def get_hub_review(review_id: int) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_reviews WHERE id = ?', (review_id,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def get_hub_review_by_date(date: str, review_type: str = 'daily') -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_reviews WHERE date = ? AND type = ?', (date, review_type))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def create_hub_review(review_type: str, date: str, data: str = None, energy: int = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO hub_reviews (type, date, data, energy)
        VALUES (?, ?, ?, ?)
    ''', (review_type, date, data, energy))
    review_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return review_id

def update_hub_review(review_id: int, data: str = None, energy: int = None) -> bool:

    conn = get_connection()
    cursor = conn.cursor()

    updates = []
    params = []

    if data is not None:
        updates.append('data = ?')
        params.append(data)
    if energy is not None:
        updates.append('energy = ?')
        params.append(energy)

    if not updates:
        conn.close()
        return False

    updates.append('updated_at = CURRENT_TIMESTAMP')
    params.append(review_id)

    cursor.execute(f'''
        UPDATE hub_reviews SET {', '.join(updates)} WHERE id = ?
    ''', params)
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def delete_hub_review(review_id: int) -> bool:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_reviews WHERE id = ?', (review_id,))
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def get_hub_training_sessions(session_type: str = None, limit: int = 50) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    if session_type:
        cursor.execute('''
            SELECT * FROM hub_training_sessions WHERE type = ?
            ORDER BY date DESC LIMIT ?
        ''', (session_type, limit))
    else:
        cursor.execute('''
            SELECT * FROM hub_training_sessions
            ORDER BY date DESC LIMIT ?
        ''', (limit,))

    sessions = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return sessions

def get_hub_training_session(session_id: int) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_training_sessions WHERE id = ?', (session_id,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def create_hub_training_session(session_type: str, date: str, duration: int = None,
                                 notes: str = None, calories: int = None,
                                 exercises: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO hub_training_sessions (type, date, duration, notes, calories, exercises)
        VALUES (?, ?, ?, ?, ?, ?)
    ''', (session_type, date, duration, notes, calories, exercises))
    session_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return session_id

def update_hub_training_session(session_id: int, session_type: str = None, date: str = None,
                                 duration: int = None, notes: str = None, calories: int = None,
                                 exercises: str = None) -> bool:

    conn = get_connection()
    cursor = conn.cursor()

    updates = []
    params = []

    if session_type is not None:
        updates.append('type = ?')
        params.append(session_type)
    if date is not None:
        updates.append('date = ?')
        params.append(date)
    if duration is not None:
        updates.append('duration = ?')
        params.append(duration)
    if notes is not None:
        updates.append('notes = ?')
        params.append(notes)
    if calories is not None:
        updates.append('calories = ?')
        params.append(calories)
    if exercises is not None:
        updates.append('exercises = ?')
        params.append(exercises)

    if not updates:
        conn.close()
        return False

    params.append(session_id)

    cursor.execute(f'''
        UPDATE hub_training_sessions SET {', '.join(updates)} WHERE id = ?
    ''', params)
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def delete_hub_training_session(session_id: int) -> bool:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_training_sessions WHERE id = ?', (session_id,))
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def get_hub_training_health(limit: int = 30) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT * FROM hub_training_health
        ORDER BY date DESC LIMIT ?
    ''', (limit,))
    logs = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return logs

def get_hub_training_health_by_date(date: str) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_training_health WHERE date = ?', (date,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def create_hub_training_health(date: str, sleep: float = None, energy: int = None,
                                stress: int = None, recovery: int = None,
                                weight: float = None, notes: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO hub_training_health (date, sleep, energy, stress, recovery, weight, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (date, sleep, energy, stress, recovery, weight, notes))
    log_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return log_id

def update_hub_training_health(log_id: int, sleep: float = None, energy: int = None,
                                stress: int = None, recovery: int = None,
                                weight: float = None, notes: str = None) -> bool:

    conn = get_connection()
    cursor = conn.cursor()

    updates = []
    params = []

    if sleep is not None:
        updates.append('sleep = ?')
        params.append(sleep)
    if energy is not None:
        updates.append('energy = ?')
        params.append(energy)
    if stress is not None:
        updates.append('stress = ?')
        params.append(stress)
    if recovery is not None:
        updates.append('recovery = ?')
        params.append(recovery)
    if weight is not None:
        updates.append('weight = ?')
        params.append(weight)
    if notes is not None:
        updates.append('notes = ?')
        params.append(notes)

    if not updates:
        conn.close()
        return False

    params.append(log_id)

    cursor.execute(f'''
        UPDATE hub_training_health SET {', '.join(updates)} WHERE id = ?
    ''', params)
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def delete_hub_training_health(log_id: int) -> bool:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_training_health WHERE id = ?', (log_id,))
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def get_hub_training_health_by_id(log_id: int) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_training_health WHERE id = ?', (log_id,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def get_hub_training_goals(completed: bool = None) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    if completed is not None:
        cursor.execute('''
            SELECT * FROM hub_training_goals WHERE completed = ?
            ORDER BY deadline ASC, created_at DESC
        ''', (1 if completed else 0,))
    else:
        cursor.execute('''
            SELECT * FROM hub_training_goals
            ORDER BY completed ASC, deadline ASC, created_at DESC
        ''')

    goals = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return goals

def get_hub_training_goal(goal_id: int) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_training_goals WHERE id = ?', (goal_id,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def create_hub_training_goal(title: str, target: float = None, current: float = 0,
                              unit: str = None, deadline: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO hub_training_goals (title, target, current, unit, deadline)
        VALUES (?, ?, ?, ?, ?)
    ''', (title, target, current, unit, deadline))
    goal_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return goal_id

def update_hub_training_goal(goal_id: int, title: str = None, target: float = None,
                              current: float = None, unit: str = None, deadline: str = None,
                              completed: bool = None) -> bool:

    conn = get_connection()
    cursor = conn.cursor()

    updates = []
    params = []

    if title is not None:
        updates.append('title = ?')
        params.append(title)
    if target is not None:
        updates.append('target = ?')
        params.append(target)
    if current is not None:
        updates.append('current = ?')
        params.append(current)
    if unit is not None:
        updates.append('unit = ?')
        params.append(unit)
    if deadline is not None:
        updates.append('deadline = ?')
        params.append(deadline)
    if completed is not None:
        updates.append('completed = ?')
        params.append(1 if completed else 0)

    if not updates:
        conn.close()
        return False

    updates.append('updated_at = CURRENT_TIMESTAMP')
    params.append(goal_id)

    cursor.execute(f'''
        UPDATE hub_training_goals SET {', '.join(updates)} WHERE id = ?
    ''', params)
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def delete_hub_training_goal(goal_id: int) -> bool:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_training_goals WHERE id = ?', (goal_id,))
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def get_timetable_settings(user_id: str = None) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('SELECT * FROM hub_timetable_settings WHERE user_id = ? ORDER BY id DESC LIMIT 1', (user_id,))
    else:

        cursor.execute('SELECT * FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def save_timetable_settings(has_ab_weeks: bool = True, block_count: int = 4,
                            reference_date: str = None, setup_completed: bool = False,
                            user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()

    if user_id:
        cursor.execute('SELECT id FROM hub_timetable_settings WHERE user_id = ? LIMIT 1', (user_id,))
    else:

        cursor.execute('SELECT id FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    existing = cursor.fetchone()

    if existing:
        cursor.execute('''
            UPDATE hub_timetable_settings
            SET has_ab_weeks = ?, block_count = ?, reference_date = ?,
                setup_completed = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ''', (1 if has_ab_weeks else 0, block_count, reference_date,
              1 if setup_completed else 0, existing['id']))
        settings_id = existing['id']
    else:
        cursor.execute('''
            INSERT INTO hub_timetable_settings (has_ab_weeks, block_count, reference_date, setup_completed, user_id)
            VALUES (?, ?, ?, ?, ?)
        ''', (1 if has_ab_weeks else 0, block_count, reference_date, 1 if setup_completed else 0, user_id))
        settings_id = cursor.lastrowid

    conn.commit()
    conn.close()
    return settings_id

def get_user_theme(user_id: str = None) -> str:
    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('SELECT theme FROM hub_timetable_settings WHERE user_id = ? ORDER BY id DESC LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT theme FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    row = cursor.fetchone()
    conn.close()
    if row and row['theme']:
        return row['theme']
    return 'dark'

def save_user_theme(theme: str, user_id: str = None) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('SELECT id FROM hub_timetable_settings WHERE user_id = ? LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT id FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    existing = cursor.fetchone()
    if existing:
        cursor.execute('UPDATE hub_timetable_settings SET theme = ? WHERE id = ?', (theme, existing['id']))
    else:
        cursor.execute('INSERT INTO hub_timetable_settings (theme, user_id) VALUES (?, ?)', (theme, user_id))
    conn.commit()
    conn.close()
    return True

def get_theme_preferences(user_id: str = None) -> Dict[str, Any]:
    settings = get_timetable_settings(user_id)
    if settings:
        return {
            'theme': settings.get('theme', 'dark'),
            'theme_mode': settings.get('theme_mode', 'manual'),
            'theme_schedule_json': settings.get('theme_schedule_json'),
        }
    return {'theme': 'dark', 'theme_mode': 'manual', 'theme_schedule_json': None}

def save_theme_preferences(theme_mode: str, theme_schedule_json: str = None, user_id: str = None) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('SELECT id FROM hub_timetable_settings WHERE user_id = ? LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT id FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    existing = cursor.fetchone()
    if existing:
        cursor.execute('''
            UPDATE hub_timetable_settings
            SET theme_mode = ?, theme_schedule_json = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ''', (theme_mode, theme_schedule_json, existing['id']))
    else:
        cursor.execute('''
            INSERT INTO hub_timetable_settings (theme_mode, theme_schedule_json, user_id)
            VALUES (?, ?, ?)
        ''', (theme_mode, theme_schedule_json, user_id))
    conn.commit()
    conn.close()
    return True

TOUR_STATES = ('done', 'skipped')

def get_tour_state(user_id: str = None) -> Optional[str]:
    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('SELECT tour_state FROM hub_timetable_settings WHERE user_id = ? ORDER BY id DESC LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT tour_state FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    row = cursor.fetchone()
    conn.close()
    if row and row['tour_state'] in TOUR_STATES:
        return row['tour_state']
    return None

def save_tour_state(state: str, user_id: str = None) -> bool:
    if state not in TOUR_STATES:
        raise ValueError(f'Unknown tour state: {state}')
    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('SELECT id FROM hub_timetable_settings WHERE user_id = ? LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT id FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    existing = cursor.fetchone()
    if existing:
        cursor.execute('UPDATE hub_timetable_settings SET tour_state = ? WHERE id = ?', (state, existing['id']))
    else:
        cursor.execute('INSERT INTO hub_timetable_settings (tour_state, user_id) VALUES (?, ?)', (state, user_id))
    conn.commit()
    conn.close()
    return True

UI_STORE_MAX_BYTES = 262144


def get_ui_store() -> Dict[str, Any]:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, 'SELECT key, value FROM ui_store')
    rows = _fetchall_dict(cursor)
    conn.close()
    values = {}
    for row in rows:
        try:
            values[row['key']] = json.loads(row['value'])
        except (TypeError, ValueError):
            continue
    return values


def save_ui_value(key: str, value: Any) -> None:
    raw = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    if len(raw.encode('utf-8')) > UI_STORE_MAX_BYTES:
        raise ValueError('value too large')
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, '''
        INSERT INTO ui_store (key, value, updated_at) VALUES (?, ?, ?)
        ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
    ''', (key, raw, datetime.now().isoformat(timespec='seconds')))
    conn.commit()
    conn.close()


def delete_ui_value(key: str) -> None:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, 'DELETE FROM ui_store WHERE key = ?', (key,))
    conn.commit()
    conn.close()


def has_hub_tasks(user_id: str = None) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('SELECT 1 FROM hub_tasks WHERE user_id = ? LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT 1 FROM hub_tasks LIMIT 1')
    row = cursor.fetchone()
    conn.close()
    return row is not None

def get_timetable_entries(day: int = None, week: str = None, user_id: str = None) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    query = 'SELECT * FROM hub_timetable_entries WHERE 1=1'
    params = []

    if user_id:
        query += ' AND user_id = ?'
        params.append(user_id)

    if day is not None:
        query += ' AND day = ?'
        params.append(day)

    if week is not None:
        query += ' AND (week = ? OR week = "both")'
        params.append(week)

    query += ' ORDER BY day, block'
    cursor.execute(query, params)
    entries = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return entries

def get_timetable_entry(entry_id: int) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_timetable_entries WHERE id = ?', (entry_id,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def create_timetable_entry(day: int, block: int, subject: str, week: str = 'both',
                           subject_type: str = 'GK', room: str = None,
                           teacher: str = None, color: str = None, user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO hub_timetable_entries (day, block, week, subject, subject_type, room, teacher, color, user_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (day, block, week, subject, subject_type, room, teacher, color, user_id))
    entry_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return entry_id

def update_timetable_entry(entry_id: int, day: int = None, block: int = None,
                           subject: str = None, week: str = None, subject_type: str = None,
                           room: str = None, teacher: str = None, color: str = None) -> bool:

    conn = get_connection()
    cursor = conn.cursor()

    updates = []
    params = []

    if day is not None:
        updates.append('day = ?')
        params.append(day)
    if block is not None:
        updates.append('block = ?')
        params.append(block)
    if subject is not None:
        updates.append('subject = ?')
        params.append(subject)
    if week is not None:
        updates.append('week = ?')
        params.append(week)
    if subject_type is not None:
        updates.append('subject_type = ?')
        params.append(subject_type)
    if room is not None:
        updates.append('room = ?')
        params.append(room)
    if teacher is not None:
        updates.append('teacher = ?')
        params.append(teacher)
    if color is not None:
        updates.append('color = ?')
        params.append(color)

    if not updates:
        conn.close()
        return False

    updates.append('updated_at = CURRENT_TIMESTAMP')
    params.append(entry_id)

    cursor.execute(f'''
        UPDATE hub_timetable_entries SET {', '.join(updates)} WHERE id = ?
    ''', params)
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def delete_timetable_entry(entry_id: int) -> bool:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_timetable_entries WHERE id = ?', (entry_id,))
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def clear_timetable(user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('DELETE FROM hub_timetable_entries WHERE user_id = ?', (user_id,))
    else:

        cursor.execute('DELETE FROM hub_timetable_entries')
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected

def import_timetable_template(entries: List[Dict[str, Any]], user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()

    count = 0
    for entry in entries:
        cursor.execute('''
            INSERT INTO hub_timetable_entries (day, block, week, subject, subject_type, room, teacher, color, user_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            entry.get('day'),
            entry.get('block'),
            entry.get('week', 'both'),
            entry.get('subject'),
            entry.get('subject_type', 'GK'),
            entry.get('room'),
            entry.get('teacher'),
            entry.get('color'),
            user_id
        ))
        count += 1

    conn.commit()
    conn.close()
    return count

def get_training_schedule_settings(user_id: str = None) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        cursor.execute('SELECT * FROM hub_training_schedule_settings WHERE user_id = ? ORDER BY id DESC LIMIT 1', (user_id,))
    else:

        cursor.execute('SELECT * FROM hub_training_schedule_settings ORDER BY id DESC LIMIT 1')
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def save_training_schedule_settings(schedule_mode: str = 'regular',
                                    auto_detect_holiday: bool = True,
                                    setup_completed: bool = False,
                                    user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()

    if user_id:
        cursor.execute('SELECT id FROM hub_training_schedule_settings WHERE user_id = ? LIMIT 1', (user_id,))
    else:

        cursor.execute('SELECT id FROM hub_training_schedule_settings ORDER BY id DESC LIMIT 1')
    existing = cursor.fetchone()

    if existing:
        cursor.execute('''
            UPDATE hub_training_schedule_settings
            SET schedule_mode = ?, auto_detect_holiday = ?,
                setup_completed = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ''', (schedule_mode, 1 if auto_detect_holiday else 0,
              1 if setup_completed else 0, existing['id']))
        settings_id = existing['id']
    else:
        cursor.execute('''
            INSERT INTO hub_training_schedule_settings (schedule_mode, auto_detect_holiday, setup_completed, user_id)
            VALUES (?, ?, ?, ?)
        ''', (schedule_mode, 1 if auto_detect_holiday else 0, 1 if setup_completed else 0, user_id))
        settings_id = cursor.lastrowid

    conn.commit()
    conn.close()
    return settings_id

def get_training_schedule_entries(day: int = None, schedule_type: str = None, user_id: str = None) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    query = 'SELECT * FROM hub_training_schedule_entries WHERE 1=1'
    params = []

    if user_id:
        query += ' AND user_id = ?'
        params.append(user_id)

    if day is not None:
        query += ' AND day = ?'
        params.append(day)

    if schedule_type is not None:
        query += ' AND schedule_type = ?'
        params.append(schedule_type)

    query += ' ORDER BY day'
    cursor.execute(query, params)
    entries = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return entries

def get_training_schedule_entry(entry_id: int) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM hub_training_schedule_entries WHERE id = ?', (entry_id,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None

def create_training_schedule_entry(day: int, training_type: str, title: str,
                                   schedule_type: str = 'regular', time: str = None,
                                   duration: int = None, location: str = None,
                                   muscle_groups: str = None, notes: str = None,
                                   icon: str = None, color: str = None, user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO hub_training_schedule_entries
        (day, schedule_type, training_type, title, time, duration, location, muscle_groups, notes, icon, color, user_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (day, schedule_type, training_type, title, time, duration, location, muscle_groups, notes, icon, color, user_id))
    entry_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return entry_id

def update_training_schedule_entry(entry_id: int, day: int = None, schedule_type: str = None,
                                   training_type: str = None, title: str = None,
                                   time: str = None, duration: int = None,
                                   location: str = None, muscle_groups: str = None,
                                   notes: str = None, icon: str = None, color: str = None) -> bool:
    conn = get_connection()
    cursor = conn.cursor()

    updates = []
    params = []

    if day is not None:
        updates.append('day = ?')
        params.append(day)
    if schedule_type is not None:
        updates.append('schedule_type = ?')
        params.append(schedule_type)
    if training_type is not None:
        updates.append('training_type = ?')
        params.append(training_type)
    if title is not None:
        updates.append('title = ?')
        params.append(title)
    if time is not None:
        updates.append('time = ?')
        params.append(time)
    if duration is not None:
        updates.append('duration = ?')
        params.append(duration)
    if location is not None:
        updates.append('location = ?')
        params.append(location)
    if muscle_groups is not None:
        updates.append('muscle_groups = ?')
        params.append(muscle_groups)
    if notes is not None:
        updates.append('notes = ?')
        params.append(notes)
    if icon is not None:
        updates.append('icon = ?')
        params.append(icon)
    if color is not None:
        updates.append('color = ?')
        params.append(color)

    if not updates:
        conn.close()
        return False

    updates.append('updated_at = CURRENT_TIMESTAMP')
    params.append(entry_id)

    cursor.execute(f'''
        UPDATE hub_training_schedule_entries SET {', '.join(updates)} WHERE id = ?
    ''', params)
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def delete_training_schedule_entry(entry_id: int) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_training_schedule_entries WHERE id = ?', (entry_id,))
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected > 0

def clear_training_schedule(schedule_type: str = None, user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()

    if user_id:
        if schedule_type:
            cursor.execute('DELETE FROM hub_training_schedule_entries WHERE schedule_type = ? AND user_id = ?', (schedule_type, user_id))
        else:
            cursor.execute('DELETE FROM hub_training_schedule_entries WHERE user_id = ?', (user_id,))
    else:

        if schedule_type:
            cursor.execute('DELETE FROM hub_training_schedule_entries WHERE schedule_type = ?', (schedule_type,))
        else:
            cursor.execute('DELETE FROM hub_training_schedule_entries')

    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected

def import_training_schedule_template(entries: List[Dict[str, Any]], user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()

    count = 0
    for entry in entries:
        cursor.execute('''
            INSERT INTO hub_training_schedule_entries
            (day, schedule_type, training_type, title, time, duration, location, muscle_groups, notes, icon, color, user_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            entry.get('day'),
            entry.get('schedule_type', 'regular'),
            entry.get('training_type'),
            entry.get('title'),
            entry.get('time'),
            entry.get('duration'),
            entry.get('location'),
            entry.get('muscle_groups'),
            entry.get('notes'),
            entry.get('icon'),
            entry.get('color'),
            user_id
        ))
        count += 1

    conn.commit()
    conn.close()
    return count

def create_pomodoro_session(subject_id: str = None, duration: int = 25, session_type: str = 'work') -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO pomodoro_sessions (subject_id, duration, session_type)
        VALUES (?, ?, ?)
    ''', (subject_id, duration, session_type))
    session_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return session_id

def get_pomodoro_sessions(limit: int = 50) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT * FROM pomodoro_sessions
        ORDER BY completed_at DESC
        LIMIT ?
    ''', (limit,))
    sessions = _fetchall_dict(cursor)
    conn.close()
    return sessions

def get_pomodoro_stats(range_type: str = 'week') -> Dict[str, Any]:

    conn = get_connection()
    cursor = conn.cursor()

    if range_type == 'today':
        date_filter = "DATE(completed_at) = DATE('now', 'localtime')"
    elif range_type == 'week':
        date_filter = "DATE(completed_at) >= DATE('now', 'localtime', '-7 days')"
    elif range_type == 'month':
        date_filter = "DATE(completed_at) >= DATE('now', 'localtime', '-30 days')"
    else:
        date_filter = "1=1"

    cursor.execute(f'''
        SELECT
            COUNT(*) as total_sessions,
            COALESCE(SUM(duration), 0) as total_minutes
        FROM pomodoro_sessions
        WHERE session_type = 'work' AND {date_filter}
    ''')
    totals = _fetchone_dict(cursor)

    cursor.execute(f'''
        SELECT
            subject_id,
            COUNT(*) as sessions,
            SUM(duration) as minutes
        FROM pomodoro_sessions
        WHERE session_type = 'work' AND {date_filter}
        GROUP BY subject_id
        ORDER BY minutes DESC
    ''')
    by_subject = _fetchall_dict(cursor)

    conn.close()

    return {
        'total_sessions': totals['total_sessions'] if totals else 0,
        'total_minutes': totals['total_minutes'] if totals else 0,
        'by_subject': by_subject
    }

def get_holidays(bundesland: str = None, year: int = None, holiday_type: str = None,
                 user_id: str = None) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    query = 'SELECT * FROM hub_holidays WHERE 1=1'
    params = []

    if bundesland:
        query += ' AND bundesland = ?'
        params.append(bundesland)
    if year:
        query += ' AND year = ?'
        params.append(year)
    if holiday_type:
        query += ' AND type = ?'
        params.append(holiday_type)
    if user_id:
        query += ' AND user_id = ?'
        params.append(user_id)

    query += ' ORDER BY date ASC'
    cursor.execute(query, params)
    holidays = _fetchall_dict(cursor)
    conn.close()
    return holidays

def get_holidays_for_date_range(start_date: str, end_date: str, bundesland: str = None,
                                 user_id: str = None) -> List[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    query = '''
        SELECT * FROM hub_holidays
        WHERE (date >= ? AND date <= ?)
           OR (end_date IS NOT NULL AND date <= ? AND end_date >= ?)
    '''
    params = [start_date, end_date, end_date, start_date]

    if bundesland:
        query += ' AND bundesland = ?'
        params.append(bundesland)
    if user_id:
        query += ' AND user_id = ?'
        params.append(user_id)

    query += ' ORDER BY date ASC'
    cursor.execute(query, params)
    holidays = _fetchall_dict(cursor)
    conn.close()
    return holidays

def create_holiday(date: str, name: str, bundesland: str, year: int,
                   end_date: str = None, holiday_type: str = 'feiertag',
                   user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO hub_holidays (date, end_date, name, type, bundesland, year, user_id)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (date, end_date, name, holiday_type, bundesland, year, user_id))
    holiday_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return holiday_id

def import_holidays(holidays: List[Dict[str, Any]], bundesland: str, user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()

    count = 0
    for h in holidays:
        cursor.execute('''
            INSERT INTO hub_holidays (date, end_date, name, type, bundesland, year, user_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            h.get('date'),
            h.get('end_date'),
            h.get('name'),
            h.get('type', 'feiertag'),
            bundesland,
            h.get('year'),
            user_id
        ))
        count += 1

    conn.commit()
    conn.close()
    return count

def clear_holidays(bundesland: str = None, year: int = None, user_id: str = None) -> int:

    conn = get_connection()
    cursor = conn.cursor()

    query = 'DELETE FROM hub_holidays WHERE 1=1'
    params = []

    if bundesland:
        query += ' AND bundesland = ?'
        params.append(bundesland)
    if year:
        query += ' AND year = ?'
        params.append(year)
    if user_id:
        query += ' AND user_id = ?'
        params.append(user_id)

    cursor.execute(query, params)
    affected = cursor.rowcount
    conn.commit()
    conn.close()
    return affected

def is_holiday(date: str, bundesland: str = None, user_id: str = None) -> Optional[Dict[str, Any]]:

    conn = get_connection()
    cursor = conn.cursor()

    query = '''
        SELECT * FROM hub_holidays
        WHERE (date = ? OR (end_date IS NOT NULL AND date <= ? AND end_date >= ?))
    '''
    params = [date, date, date]

    if bundesland:
        query += ' AND bundesland = ?'
        params.append(bundesland)
    if user_id:
        query += ' AND user_id = ?'
        params.append(user_id)

    query += ' LIMIT 1'
    cursor.execute(query, params)
    holiday = _fetchone_dict(cursor)
    conn.close()
    return holiday

def get_bundesland_setting(user_id: str = None) -> Optional[str]:

    settings = get_timetable_settings(user_id)
    if settings:
        return settings.get('bundesland')
    return None

def save_bundesland_setting(bundesland: str, holidays_imported_until: int = None,
                            user_id: str = None) -> bool:

    conn = get_connection()
    cursor = conn.cursor()

    if user_id:
        cursor.execute('SELECT id FROM hub_timetable_settings WHERE user_id = ? LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT id FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    existing = cursor.fetchone()

    if existing:
        update_parts = ['bundesland = ?', 'updated_at = CURRENT_TIMESTAMP']
        params = [bundesland]
        if holidays_imported_until:
            update_parts.append('holidays_imported_until = ?')
            params.append(holidays_imported_until)
        params.append(existing['id'])

        cursor.execute(f'''
            UPDATE hub_timetable_settings SET {', '.join(update_parts)} WHERE id = ?
        ''', params)
    else:
        cursor.execute('''
            INSERT INTO hub_timetable_settings (bundesland, holidays_imported_until, user_id)
            VALUES (?, ?, ?)
        ''', (bundesland, holidays_imported_until, user_id))

    conn.commit()
    conn.close()
    return True

def get_birthday_setting(user_id: str = None) -> Optional[str]:
    settings = get_timetable_settings(user_id)
    if settings:
        return settings.get('birthday')
    return None

def save_birthday_setting(birthday: str, user_id: str = None) -> bool:
    conn = get_connection()
    cursor = conn.cursor()

    if user_id:
        cursor.execute('SELECT id FROM hub_timetable_settings WHERE user_id = ? LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT id FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    existing = cursor.fetchone()

    if existing:
        cursor.execute('''
            UPDATE hub_timetable_settings SET birthday = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
        ''', (birthday, existing['id']))
    else:
        cursor.execute('''
            INSERT INTO hub_timetable_settings (birthday, user_id) VALUES (?, ?)
        ''', (birthday, user_id))

    conn.commit()
    conn.close()
    return True

def get_location_setting(user_id: str = None) -> Optional[str]:
    settings = get_timetable_settings(user_id)
    if settings:
        return settings.get('location_json')
    return None

def save_location_setting(location_json: str, user_id: str = None) -> bool:
    conn = get_connection()
    cursor = conn.cursor()

    if user_id:
        cursor.execute('SELECT id FROM hub_timetable_settings WHERE user_id = ? LIMIT 1', (user_id,))
    else:
        cursor.execute('SELECT id FROM hub_timetable_settings ORDER BY id DESC LIMIT 1')
    existing = cursor.fetchone()

    if existing:
        cursor.execute('''
            UPDATE hub_timetable_settings SET location_json = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
        ''', (location_json, existing['id']))
    else:
        cursor.execute('''
            INSERT INTO hub_timetable_settings (location_json, user_id) VALUES (?, ?)
        ''', (location_json, user_id))

    conn.commit()
    conn.close()
    return True


def get_timetable_periods() -> List[Dict[str, Any]]:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, 'SELECT * FROM hub_timetable_periods ORDER BY period_number')
    result = _fetchall_dict(cursor)
    conn.close()
    return result


def replace_all_timetable_periods(periods: list) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_timetable_periods')
    for p in periods:
        cursor.execute(
            'INSERT INTO hub_timetable_periods (period_number, start_time, end_time) VALUES (?, ?, ?)',
            (p['period_number'], p['start_time'], p['end_time'])
        )
    conn.commit()
    conn.close()
    return True


def delete_timetable_period(period_number: int) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM hub_timetable_periods WHERE period_number = ?', (period_number,))
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def get_hub_bookmarks(category: str = None) -> List[Dict[str, Any]]:
    conn = get_connection()
    cursor = conn.cursor()
    if category and category != 'all':
        _execute(cursor, 'SELECT * FROM hub_bookmarks WHERE category = ? ORDER BY created_at DESC', (category,))
    else:
        _execute(cursor, 'SELECT * FROM hub_bookmarks ORDER BY created_at DESC')
    result = _fetchall_dict(cursor)
    conn.close()
    return result

def get_hub_bookmark(bookmark_id: int) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, 'SELECT * FROM hub_bookmarks WHERE id = ?', (bookmark_id,))
    result = _fetchone_dict(cursor)
    conn.close()
    return result

def create_hub_bookmark(title: str, url: str, category: str = 'Other', favicon: str = None) -> int:
    conn = get_connection()
    cursor = conn.cursor()
    now = datetime.now().isoformat()
    _execute(cursor, '''
        INSERT INTO hub_bookmarks (title, url, category, favicon, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ''', (title, url, category, favicon, now, now))
    bookmark_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return bookmark_id

def update_hub_bookmark(bookmark_id: int, **kwargs) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    updates = []
    params = []
    for key in ('title', 'url', 'category', 'favicon'):
        if key in kwargs and kwargs[key] is not None:
            updates.append(f'{key} = ?')
            params.append(kwargs[key])
    if not updates:
        conn.close()
        return False
    updates.append('updated_at = ?')
    params.append(datetime.now().isoformat())
    params.append(bookmark_id)
    _execute(cursor, f'UPDATE hub_bookmarks SET {", ".join(updates)} WHERE id = ?', params)
    conn.commit()
    conn.close()
    return True

def delete_hub_bookmark(bookmark_id: int) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, 'DELETE FROM hub_bookmarks WHERE id = ?', (bookmark_id,))
    conn.commit()
    conn.close()
    return True


def get_user_tickets(user_id: str = None) -> List[Dict[str, Any]]:
    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        _execute(cursor, 'SELECT * FROM hub_user_tickets WHERE user_id = ? AND is_active = 1 ORDER BY created_at DESC', (user_id,))
    else:
        _execute(cursor, 'SELECT * FROM hub_user_tickets WHERE is_active = 1 ORDER BY created_at DESC')
    rows = cursor.fetchall()
    conn.close()
    return [dict(r) for r in rows]

def create_user_ticket(ticket_type: str, ticket_name: str, zone_coverage: str,
                       valid_from: str = None, valid_until: str = None,
                       auto_renews: bool = False, user_id: str = None) -> int:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, '''
        INSERT INTO hub_user_tickets (ticket_type, ticket_name, zone_coverage, valid_from, valid_until, auto_renews, user_id)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (ticket_type, ticket_name, zone_coverage, valid_from, valid_until, 1 if auto_renews else 0, user_id))
    ticket_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return ticket_id

def update_user_ticket(ticket_id: int, **kwargs) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    updates = []
    params = []
    for key in ('ticket_type', 'ticket_name', 'zone_coverage', 'valid_from', 'valid_until', 'auto_renews', 'is_active'):
        if key in kwargs and kwargs[key] is not None:
            updates.append(f'{key} = ?')
            val = kwargs[key]
            if key in ('auto_renews', 'is_active') and isinstance(val, bool):
                val = 1 if val else 0
            params.append(val)
    if not updates:
        conn.close()
        return False
    updates.append('updated_at = CURRENT_TIMESTAMP')
    params.append(ticket_id)
    _execute(cursor, f'UPDATE hub_user_tickets SET {", ".join(updates)} WHERE id = ?', params)
    conn.commit()
    conn.close()
    return True

def delete_user_ticket(ticket_id: int) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, 'DELETE FROM hub_user_tickets WHERE id = ?', (ticket_id,))
    conn.commit()
    conn.close()
    return True


def get_monitored_routes(user_id: str = None, status: str = 'active') -> List[Dict[str, Any]]:
    conn = get_connection()
    cursor = conn.cursor()
    if user_id:
        _execute(cursor, 'SELECT * FROM hub_monitored_routes WHERE user_id = ? AND status = ? ORDER BY departure_time ASC', (user_id, status))
    else:
        _execute(cursor, 'SELECT * FROM hub_monitored_routes WHERE status = ? ORDER BY departure_time ASC', (status,))
    rows = cursor.fetchall()
    conn.close()
    return [dict(r) for r in rows]

def create_monitored_route(route_data: str, from_name: str, to_name: str,
                           departure_time: str, user_id: str = None) -> int:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, '''
        INSERT INTO hub_monitored_routes (route_data, from_name, to_name, departure_time, user_id)
        VALUES (?, ?, ?, ?, ?)
    ''', (route_data, from_name, to_name, departure_time, user_id))
    route_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return route_id

def update_monitored_route(route_id: int, **kwargs) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    updates = []
    params = []
    for key in ('status', 'last_check', 'current_delays', 'notifications_sent'):
        if key in kwargs and kwargs[key] is not None:
            updates.append(f'{key} = ?')
            params.append(kwargs[key])
    if not updates:
        conn.close()
        return False
    params.append(route_id)
    _execute(cursor, f'UPDATE hub_monitored_routes SET {", ".join(updates)} WHERE id = ?', params)
    conn.commit()
    conn.close()
    return True

def delete_monitored_route(route_id: int) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    _execute(cursor, 'DELETE FROM hub_monitored_routes WHERE id = ?', (route_id,))
    conn.commit()
    conn.close()
    return True

init_db()
