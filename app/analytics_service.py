# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

"""
Analytics service for the smart dashboard.
Computes productivity trends, grade analytics, health correlations, and more.
"""

from datetime import datetime, timedelta
from . import database as db

DAY_NAMES_DE = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag']


def _date_n_days_ago(days):
    return (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')


def _safe_div(a, b):
    return round(a / b, 2) if b else 0


def _pearson(x_vals, y_vals):
    n = len(x_vals)
    if n < 5:
        return None
    mx = sum(x_vals) / n
    my = sum(y_vals) / n
    num = sum((x - mx) * (y - my) for x, y in zip(x_vals, y_vals))
    dx = sum((x - mx) ** 2 for x in x_vals) ** 0.5
    dy = sum((y - my) ** 2 for y in y_vals) ** 0.5
    if dx == 0 or dy == 0:
        return None
    return round(num / (dx * dy), 3)


def _correlation_description(r):
    if r is None:
        return 'Nicht genug Daten'
    ar = abs(r)
    direction = 'positiv' if r > 0 else 'negativ'
    if ar >= 0.7:
        return f'Stark {direction} (r={r})'
    if ar >= 0.4:
        return f'Moderat {direction} (r={r})'
    if ar >= 0.2:
        return f'Schwach {direction} (r={r})'
    return f'Kein Zusammenhang (r={r})'


def _linear_slope(values):
    n = len(values)
    if n < 2:
        return 0
    x_vals = list(range(n))
    mx = (n - 1) / 2
    my = sum(values) / n
    num = sum((x - mx) * (y - my) for x, y in zip(x_vals, values))
    den = sum((x - mx) ** 2 for x in x_vals)
    if den == 0:
        return 0
    return round(num / den, 4)


def get_productivity_trends(days):
    cutoff = _date_n_days_ago(days)
    conn = db.get_connection()
    cursor = conn.cursor()

    cursor.execute('''
        SELECT DATE(completed_at) as date, COUNT(*) as count
        FROM hub_tasks
        WHERE completed = 1 AND DATE(completed_at) >= ?
        GROUP BY DATE(completed_at)
        ORDER BY date
    ''', (cutoff,))
    task_rows = {row['date']: row['count'] for row in cursor.fetchall()}

    cursor.execute('''
        SELECT DATE(completed_at) as date, SUM(duration) as minutes, COUNT(*) as sessions
        FROM pomodoro_sessions
        WHERE session_type = 'work' AND DATE(completed_at) >= ?
        GROUP BY DATE(completed_at)
        ORDER BY date
    ''', (cutoff,))
    pomo_rows = {row['date']: {'minutes': row['minutes'] or 0, 'sessions': row['sessions']} for row in cursor.fetchall()}
    conn.close()

    all_dates = sorted(set(list(task_rows.keys()) + list(pomo_rows.keys())))
    return {
        'dates': all_dates,
        'tasks_completed': [task_rows.get(d, 0) for d in all_dates],
        'pomodoro_minutes': [pomo_rows.get(d, {}).get('minutes', 0) for d in all_dates],
        'pomodoro_sessions': [pomo_rows.get(d, {}).get('sessions', 0) for d in all_dates],
    }


def get_task_stats(days):
    cutoff = _date_n_days_ago(days)
    conn = db.get_connection()
    cursor = conn.cursor()

    cursor.execute('''
        SELECT COUNT(*) as total FROM hub_tasks
        WHERE created_at >= ?
    ''', (cutoff,))
    total = cursor.fetchone()['total']

    cursor.execute('''
        SELECT COUNT(*) as completed FROM hub_tasks
        WHERE completed = 1 AND completed_at >= ?
    ''', (cutoff,))
    completed = cursor.fetchone()['completed']

    cursor.execute('''
        SELECT CAST(strftime('%w', completed_at) AS INTEGER) as dow, COUNT(*) as count
        FROM hub_tasks
        WHERE completed = 1 AND DATE(completed_at) >= ?
        GROUP BY dow ORDER BY count DESC
    ''', (cutoff,))
    by_dow_rows = [dict(row) for row in cursor.fetchall()]

    cursor.execute('''
        SELECT priority, COUNT(*) as count FROM hub_tasks
        WHERE completed = 1 AND completed_at >= ?
        GROUP BY priority
    ''', (cutoff,))
    by_priority = {row['priority']: row['count'] for row in cursor.fetchall()}

    cursor.execute('''
        SELECT COUNT(*) as overdue FROM hub_tasks
        WHERE completed = 0 AND due_date < DATE('now', 'localtime')
    ''')
    overdue = cursor.fetchone()['overdue']

    conn.close()

    # Convert Sunday=0 to Monday-based index
    by_dow = {}
    for row in by_dow_rows:
        idx = (row['dow'] - 1) % 7  # Monday=0
        by_dow[DAY_NAMES_DE[idx]] = row['count']

    most_productive_day = max(by_dow, key=by_dow.get) if by_dow else None

    return {
        'total_created': total,
        'total_completed': completed,
        'completion_rate': _safe_div(completed * 100, total),
        'overdue': overdue,
        'by_day_of_week': by_dow,
        'most_productive_day': most_productive_day,
        'by_priority': by_priority,
    }


def get_grade_trends(subjects, grades):
    if not subjects or not grades:
        return {'subjects': [], 'has_data': False}

    subj_map = {s.get('id', s.get('name', '')): s for s in subjects}
    by_subject = {}

    for g in grades:
        sid = g.get('subject_id', g.get('subject', ''))
        if sid not in by_subject:
            subj = subj_map.get(sid, {})
            by_subject[sid] = {
                'id': sid,
                'name': subj.get('name', str(sid)),
                'color': subj.get('color', '#888'),
                'grades': [],
            }
        by_subject[sid]['grades'].append({
            'date': g.get('date', ''),
            'value': g.get('points', g.get('grade_value', g.get('value', 0))),
            'weight': g.get('weight', 1),
        })

    result = []
    for _sid, data in by_subject.items():
        data['grades'].sort(key=lambda x: x['date'])
        values = [g['value'] for g in data['grades']]
        weights = [g['weight'] for g in data['grades']]

        weighted_sum = sum(v * w for v, w in zip(values, weights))
        weight_total = sum(weights)
        avg = _safe_div(weighted_sum, weight_total)

        slope = _linear_slope(values)
        data['average'] = avg
        data['trend_slope'] = slope
        data['trend_direction'] = 'up' if slope > 0.05 else ('down' if slope < -0.05 else 'stable')
        data['count'] = len(values)
        result.append(data)

    result.sort(key=lambda x: x['name'])
    return {'subjects': result, 'has_data': True}


def get_health_correlations(days):
    cutoff = _date_n_days_ago(days)
    health_logs = db.get_hub_training_health(limit=days)
    health_logs = [h for h in health_logs if h.get('date', '') >= cutoff]

    if len(health_logs) < 5:
        return {
            'sleep_vs_tasks': {'r': None, 'description': 'Nicht genug Daten'},
            'energy_vs_pomodoro': {'r': None, 'description': 'Nicht genug Daten'},
            'data_points': [],
        }

    conn = db.get_connection()
    cursor = conn.cursor()

    cursor.execute('''
        SELECT DATE(completed_at) as date, COUNT(*) as count
        FROM hub_tasks
        WHERE completed = 1 AND DATE(completed_at) >= ?
        GROUP BY DATE(completed_at)
    ''', (cutoff,))
    tasks_by_date = {row['date']: row['count'] for row in cursor.fetchall()}

    cursor.execute('''
        SELECT DATE(completed_at) as date, SUM(duration) as minutes
        FROM pomodoro_sessions
        WHERE session_type = 'work' AND DATE(completed_at) >= ?
        GROUP BY DATE(completed_at)
    ''', (cutoff,))
    pomo_by_date = {row['date']: row['minutes'] or 0 for row in cursor.fetchall()}
    conn.close()

    data_points = []
    sleep_vals, task_vals = [], []
    energy_vals, pomo_vals = [], []

    for h in health_logs:
        d = h['date']
        point = {
            'date': d,
            'sleep': h.get('sleep'),
            'energy': h.get('energy'),
            'tasks': tasks_by_date.get(d, 0),
            'pomodoro_min': pomo_by_date.get(d, 0),
        }
        data_points.append(point)

        if point['sleep'] is not None:
            sleep_vals.append(point['sleep'])
            task_vals.append(point['tasks'])
        if point['energy'] is not None:
            energy_vals.append(point['energy'])
            pomo_vals.append(point['pomodoro_min'])

    r_sleep = _pearson(sleep_vals, task_vals)
    r_energy = _pearson(energy_vals, pomo_vals)

    return {
        'sleep_vs_tasks': {'r': r_sleep, 'description': _correlation_description(r_sleep)},
        'energy_vs_pomodoro': {'r': r_energy, 'description': _correlation_description(r_energy)},
        'data_points': data_points,
    }


def get_training_trends(days):
    cutoff = _date_n_days_ago(days)
    sessions = db.get_hub_training_sessions(limit=500)
    sessions = [s for s in sessions if s.get('date', '') >= cutoff]

    weeks = {}
    by_type = {}
    total_duration = 0
    total_calories = 0

    for s in sessions:
        d = s.get('date', '')
        if len(d) >= 10:
            dt = datetime.strptime(d[:10], '%Y-%m-%d')
            week_key = dt.strftime('%Y-W%W')
        else:
            week_key = 'unknown'

        if week_key not in weeks:
            weeks[week_key] = {'sessions': 0, 'duration': 0, 'calories': 0}
        weeks[week_key]['sessions'] += 1
        weeks[week_key]['duration'] += s.get('duration', 0) or 0
        weeks[week_key]['calories'] += s.get('calories', 0) or 0

        t = s.get('type', 'other')
        by_type[t] = by_type.get(t, 0) + 1
        total_duration += s.get('duration', 0) or 0
        total_calories += s.get('calories', 0) or 0

    sorted_weeks = sorted(weeks.keys())
    return {
        'weeks': sorted_weeks,
        'sessions_per_week': [weeks[w]['sessions'] for w in sorted_weeks],
        'duration_per_week': [weeks[w]['duration'] for w in sorted_weeks],
        'calories_per_week': [weeks[w]['calories'] for w in sorted_weeks],
        'by_type': by_type,
        'total_sessions': len(sessions),
        'total_duration': total_duration,
        'total_calories': total_calories,
        'avg_per_week': _safe_div(len(sessions), max(len(sorted_weeks), 1)),
    }


def get_study_analytics(days, subjects):
    cutoff = _date_n_days_ago(days)
    conn = db.get_connection()
    cursor = conn.cursor()

    cursor.execute('''
        SELECT subject_id, SUM(duration) as minutes, COUNT(*) as sessions
        FROM pomodoro_sessions
        WHERE session_type = 'work' AND DATE(completed_at) >= ?
        GROUP BY subject_id
        ORDER BY minutes DESC
    ''', (cutoff,))
    pomo_data = [dict(row) for row in cursor.fetchall()]
    conn.close()

    subj_map = {s.get('id', s.get('name', '')): s for s in subjects} if subjects else {}

    by_subject = []
    total_minutes = 0
    for p in pomo_data:
        sid = p['subject_id']
        subj = subj_map.get(sid, {})
        minutes = p['minutes'] or 0
        total_minutes += minutes
        by_subject.append({
            'subject_id': sid,
            'name': subj.get('name', str(sid) if sid else 'Ohne Fach'),
            'color': subj.get('color', '#888'),
            'minutes': minutes,
            'sessions': p['sessions'],
        })

    return {
        'by_subject': by_subject,
        'total_minutes': total_minutes,
        'total_hours': round(total_minutes / 60, 1),
    }


def get_fun_facts(days):
    facts = []
    task_stats = get_task_stats(days)
    pomo_stats = db.get_pomodoro_stats('month')
    training = get_training_trends(days)

    if task_stats['most_productive_day']:
        facts.append({
            'icon': 'calendar',
            'text': f"Dein produktivster Tag ist {task_stats['most_productive_day']}",
        })

    if task_stats['total_created'] > 0:
        facts.append({
            'icon': 'check',
            'text': f"Du schaffst {task_stats['completion_rate']:.0f}% deiner Tasks",
        })

    total_hours = round((pomo_stats.get('total_minutes', 0) or 0) / 60, 1)
    if total_hours > 0:
        facts.append({
            'icon': 'clock',
            'text': f"Du hast {total_hours} Stunden mit Pomodoro gelernt (30 Tage)",
        })

    if pomo_stats.get('by_subject'):
        top = pomo_stats['by_subject'][0]
        if top.get('subject_id'):
            facts.append({
                'icon': 'book',
                'text': f"Dein meistgelerntes Fach: Fach #{top['subject_id']} ({round((top.get('minutes', 0) or 0) / 60, 1)}h)",
            })

    if training['total_sessions'] > 0:
        facts.append({
            'icon': 'dumbbell',
            'text': f"{training['total_sessions']} Trainingseinheiten, ~{training['avg_per_week']:.1f} pro Woche",
        })

    if task_stats['overdue'] > 0:
        facts.append({
            'icon': 'alert',
            'text': f"{task_stats['overdue']} überfällige Aufgaben warten auf dich",
        })

    return facts[:6]


def get_digest(days):
    task_stats = get_task_stats(days)
    productivity = get_productivity_trends(days)
    training = get_training_trends(days)

    achievements = []
    alerts = []
    trends = []

    if task_stats['total_completed'] > 0:
        achievements.append(f"{task_stats['total_completed']} Aufgaben erledigt")
    if training['total_sessions'] > 0:
        achievements.append(f"{training['total_sessions']} Trainingseinheiten absolviert")
        if training['total_duration'] > 0:
            achievements.append(f"{round(training['total_duration'] / 60, 1)}h trainiert")

    total_pomo = sum(productivity['pomodoro_minutes'])
    if total_pomo > 0:
        achievements.append(f"{round(total_pomo / 60, 1)}h mit Pomodoro gelernt")

    if task_stats['overdue'] > 0:
        alerts.append(f"{task_stats['overdue']} überfällige Aufgaben")
    if task_stats['completion_rate'] < 50 and task_stats['total_created'] >= 5:
        alerts.append(f"Nur {task_stats['completion_rate']:.0f}% Task-Abschlussrate")

    # Compare last half vs first half of period
    mid = len(productivity['tasks_completed']) // 2
    if mid > 0:
        first_half = sum(productivity['tasks_completed'][:mid])
        second_half = sum(productivity['tasks_completed'][mid:])
        if first_half > 0:
            change = _safe_div((second_half - first_half) * 100, first_half)
            if abs(change) >= 10:
                direction = '+' if change > 0 else ''
                trends.append(f"Produktivität {direction}{change:.0f}% vs. vorherige Periode")

    return {
        'period_days': days,
        'achievements': achievements,
        'alerts': alerts,
        'trends': trends,
    }
