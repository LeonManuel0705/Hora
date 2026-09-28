# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

"""
AI assistant service.
Handles LLM backends (Ollama, Claude API, offline), context building, and action execution.
"""

import json
import re
import logging
from datetime import datetime, timedelta
from pathlib import Path

from . import database as db
from .crypto_utils import encrypt_file, decrypt_file
from . import brand
from . import local_ai

import requests as http_requests
from .paths import DATA_DIR

CONFIG_FILE = DATA_DIR / 'assistant_config.json'
MODELS_DIR = DATA_DIR / 'models'

DAY_NAMES_DE = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag']

def _weekday_to_db_day(weekday):
    """Convert Python weekday (0=Mon) to DB day (1=Mon). Returns None for weekends."""
    if weekday >= 5:
        return None
    return weekday + 1
OLLAMA_BASE = 'http://localhost:11434'

# Ollama model blob paths (auto-detected)
OLLAMA_BLOBS = Path.home() / '.ollama' / 'models' / 'blobs'
OLLAMA_MANIFESTS = Path.home() / '.ollama' / 'models' / 'manifests' / 'registry.ollama.ai' / 'library'

# ---- Local LLM Singleton ----
_local_llm = None
_local_llm_path = None


def _find_local_model():
    """Find a GGUF model: prefer local models dir (Gemma 4), then Ollama blobs."""
    # Check local models directory first (Gemma 4 E2B lives here)
    if MODELS_DIR.exists():
        # Prefer gemma-4 models, then any other GGUF
        gguf_files = sorted(MODELS_DIR.glob('*.gguf'), key=lambda f: (
            0 if 'gemma-4' in f.name.lower() or 'gemma4' in f.name.lower() else 1,
            f.name
        ))
        if gguf_files:
            f = gguf_files[0]
            # Make a friendly model name
            name = f.stem.replace('-it-Q4_K_M', '').replace('-it-', ' ')
            return str(f), name

    # Fallback: Ollama blobs
    for model_name, tag in [('gemma2', '2b'), ('llama3.2', '1b')]:
        manifest = OLLAMA_MANIFESTS / model_name / tag
        if manifest.exists():
            try:
                with open(manifest) as f:
                    data = json.load(f)
                for layer in data.get('layers', []):
                    if 'model' in layer.get('mediaType', ''):
                        blob = OLLAMA_BLOBS / layer['digest'].replace(':', '-')
                        if blob.exists():
                            return str(blob), model_name + ':' + tag
            except Exception:
                continue

    return None, None


def _get_local_llm():
    global _local_llm, _local_llm_path
    model_path, model_name = _find_local_model()
    if not model_path:
        return None, None

    if _local_llm is not None and _local_llm_path == model_path:
        return _local_llm, model_name

    try:
        import os
        from llama_cpp import Llama

        # Use all physical cores minus 2 (leave headroom for Flask + OS).
        threads = max(4, (os.cpu_count() or 4) - 2)

        # Metal GPU offload on Apple Silicon — massive speedup when available.
        # Falls back cleanly to 0 if the wheel wasn't built with Metal support.
        n_gpu_layers = 0
        try:
            from llama_cpp import llama_supports_gpu_offload
            if llama_supports_gpu_offload():
                n_gpu_layers = -1
        except Exception:
            pass

        logging.info(f'Loading local LLM: {model_name} (threads={threads}, gpu_layers={n_gpu_layers})')
        _local_llm = Llama(
            model_path=model_path,
            n_ctx=8192,
            n_threads=threads,
            n_batch=1024,
            n_gpu_layers=n_gpu_layers,
            verbose=False,
        )
        _local_llm_path = model_path
        logging.info(f'Local LLM loaded: {model_name}')
        return _local_llm, model_name
    except ImportError:
        logging.warning('llama-cpp-python not installed')
        return None, None
    except Exception as e:
        logging.error(f'Failed to load local LLM: {e}')
        return None, None


def check_local_status():
    if local_ai.is_installed():
        return {'available': True, 'model': local_ai.model_label()}
    return {'available': False}


def release_local_llm():
    global _local_llm, _local_llm_path
    _local_llm = None
    _local_llm_path = None

TOOL_SCHEMAS = [
    {
        'name': 'create_task',
        'description': 'Erstellt eine neue Aufgabe im Task-Manager',
        'input_schema': {
            'type': 'object',
            'properties': {
                'title': {'type': 'string', 'description': 'Titel der Aufgabe'},
                'due_date': {'type': 'string', 'description': 'Fälligkeitsdatum im Format YYYY-MM-DD'},
                'due_time': {'type': 'string', 'description': 'Uhrzeit im Format HH:MM (optional)'},
                'priority': {'type': 'string', 'enum': ['low', 'medium', 'high'], 'description': 'Priorität'},
                'description': {'type': 'string', 'description': 'Beschreibung (optional)'},
            },
            'required': ['title'],
        },
    },
    {
        'name': 'create_homework',
        'description': 'Erstellt eine neue Hausaufgabe',
        'input_schema': {
            'type': 'object',
            'properties': {
                'title': {'type': 'string', 'description': 'Titel der Hausaufgabe'},
                'subject_id': {'type': 'string', 'description': 'Fach-ID oder Fachname'},
                'due_date': {'type': 'string', 'description': 'Fälligkeitsdatum im Format YYYY-MM-DD'},
                'description': {'type': 'string', 'description': 'Beschreibung (optional)'},
            },
            'required': ['title'],
        },
    },
]

MODEL_ACTIONS = {schema['name'] for schema in TOOL_SCHEMAS}
ACTION_MARKER = re.compile(r'\[/?ACTION\]', re.IGNORECASE)


def strip_action_markers(text):
    while True:
        stripped = ACTION_MARKER.sub('', text)
        if stripped == text:
            return text
        text = stripped


def model_action_refusal(action, message, researched):
    if not isinstance(action, dict):
        return 'Ungültige Aktion übersprungen'
    kind = action.get('name') or action.get('type')
    if not isinstance(kind, str) or kind not in MODEL_ACTIONS:
        return 'Aktion übersprungen: Der Assistent darf nur Aufgaben und Hausaufgaben anlegen'
    if researched and not _detect_creation_intent(message):
        return 'Aktion übersprungen: Die Antwort stützt sich auf Recherche-Text'
    return None

# ---- Config Management ----

def load_config():
    try:
        data = decrypt_file(CONFIG_FILE)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {
        'claude_api_key': '',
        'preferred_backend': 'auto',
        'ollama_model': 'llama3.2:1b',
        'claude_model': 'claude-sonnet-4-20250514',
    }


def save_config(config):
    encrypt_file(config, CONFIG_FILE)


def get_claude_api_key():
    return load_config().get('claude_api_key', '')


def set_claude_api_key(key):
    config = load_config()
    config['claude_api_key'] = key
    save_config(config)


# ---- Backend Detection ----

def check_ollama_status():
    try:
        resp = http_requests.get(f'{OLLAMA_BASE}/api/tags', timeout=2)
        if resp.ok:
            data = resp.json()
            models = data.get('models', [])
            return {'available': True, 'models': [m.get('name', '') for m in models]}
    except Exception:
        pass
    return {'available': False, 'models': []}


def get_ollama_models():
    status = check_ollama_status()
    return status.get('models', [])


def check_claude_status():
    key = get_claude_api_key()
    if not key:
        return {'available': False, 'reason': 'no_key'}
    try:
        import anthropic
        anthropic.Anthropic(api_key=key)
        return {'available': True}
    except ImportError:
        return {'available': False, 'reason': 'no_sdk'}
    except Exception:
        return {'available': False, 'reason': 'invalid_key'}


def get_active_backend():
    config = load_config()
    preferred = config.get('preferred_backend', 'auto')

    if preferred == 'ollama':
        if check_ollama_status()['available']:
            return 'ollama'
        return 'offline'
    elif preferred == 'claude':
        if check_claude_status()['available']:
            return 'claude'
        return 'offline'
    elif preferred == 'local':
        if check_local_status()['available']:
            return 'local'
        return 'offline'
    elif preferred == 'auto':
        if check_local_status()['available']:
            return 'local'
        if check_ollama_status()['available']:
            return 'ollama'
        if check_claude_status()['available']:
            return 'claude'
        return 'offline'

    return 'offline'


def get_status():
    config = load_config()
    backend = get_active_backend()
    model = ''
    if backend == 'ollama':
        model = config.get('ollama_model', 'llama3.2:1b')
    elif backend == 'claude':
        model = config.get('claude_model', 'claude-sonnet-4-20250514')
    elif backend == 'local':
        model = check_local_status().get('model', 'local')
    return {
        'available': backend != 'offline',
        'backend': backend,
        'model': model,
        'preferred': config.get('preferred_backend', 'auto'),
    }


# ---- Context Builder ----

def _format_date_de(date_str):
    try:
        dt = datetime.strptime(date_str[:10], '%Y-%m-%d')
        today = datetime.now().date()
        diff = (dt.date() - today).days
        if diff == 0:
            return 'heute'
        elif diff == 1:
            return 'morgen'
        elif diff == -1:
            return 'gestern'
        elif 2 <= diff <= 6:
            return f'in {diff} Tagen ({DAY_NAMES_DE[dt.weekday()]})'
        return dt.strftime('%d.%m.%Y')
    except Exception:
        return date_str


def _days_suffix(days):
    if -1 <= days <= 6:
        return ''
    if days == 1:
        return ' (in 1 Tag)'
    if days > 1:
        return f' (in {days} Tagen)'
    if days == -1:
        return ''
    return f' (vor {-days} Tagen)'


def _in_days(days):
    if days == 0:
        return 'heute'
    if days == 1:
        return 'morgen'
    if days == -1:
        return 'gestern'
    if days > 1:
        return f'in {days} Tagen'
    return f'vor {-days} Tagen'


def build_context(load_school_fn, message=None):
    now = datetime.now()
    today = now.strftime('%Y-%m-%d')
    weekday = now.weekday()

    lines = [
        f'=== {brand.NAME.upper()} KONTEXT ===',
        f'Datum: {DAY_NAMES_DE[weekday]}, {now.strftime("%d.%m.%Y")} ({now.strftime("%H:%M")} Uhr)',
        '',
    ]

    # Timetable
    try:
        settings = db.get_timetable_settings()
        has_ab = settings.get('has_ab_weeks', True) if settings else True
        ref_date = settings.get('reference_date') if settings else None

        week_type = 'both'
        if has_ab and ref_date:
            try:
                ref = datetime.strptime(ref_date, '%Y-%m-%d')
                diff_weeks = abs((now - ref).days) // 7
                week_type = 'A' if diff_weeks % 2 == 0 else 'B'
            except Exception:
                pass

        db_day = _weekday_to_db_day(weekday)
        entries = db.get_timetable_entries(day=db_day) if db_day else []
        if week_type != 'both':
            entries = [e for e in entries if e.get('week', 'both') in ('both', week_type)]
        periods = db.get_timetable_periods()
        period_map = {p['period_number']: p for p in periods}

        if entries:
            lines.append(f'--- Stundenplan ({DAY_NAMES_DE[weekday]}, Woche {week_type if week_type != "both" else ""}) ---')
            entries.sort(key=lambda e: e.get('block', 0))
            for e in entries:
                block = e.get('block', 0)
                p = period_map.get(block, {})
                time_str = f'{p.get("start_time", "?")} - {p.get("end_time", "?")}' if p else f'Block {block}'
                room = f', Raum {e["room"]}' if e.get('room') else ''
                teacher = f', {e["teacher"]}' if e.get('teacher') else ''
                subject_type = f' ({e["subject_type"]})' if e.get('subject_type') else ''
                lines.append(f'  Block {block} ({time_str}): {e.get("subject", "?")}{subject_type}{room}{teacher}')
            lines.append('')
    except Exception as ex:
        logging.debug(f'Timetable context error: {ex}')

    # Tasks
    try:
        tasks = db.get_hub_tasks('all')
        open_tasks = [t for t in tasks if not t.get('completed')][:15]
        if open_tasks:
            lines.append(f'--- Offene Aufgaben ({len(open_tasks)}) ---')
            for t in open_tasks:
                due = f' [Fällig: {_format_date_de(t["due_date"])}]' if t.get('due_date') else ''
                prio = f', Priorität: {t["priority"]}' if t.get('priority') else ''
                lines.append(f'  - {t["title"]}{due}{prio}')
            lines.append('')
    except Exception:
        pass

    # School data
    try:
        subjects, homework, exams, tests, grades = load_school_fn()
        subj_map = {s.get('id', s.get('name', '')): s.get('name', str(s.get('id', ''))) for s in subjects}

        open_hw = [h for h in homework if not h.get('completed')][:10]
        if open_hw:
            lines.append(f'--- Hausaufgaben ({len(open_hw)} offen) ---')
            for h in open_hw:
                subj_name = subj_map.get(h.get('subject_id', ''), '')
                subj_str = f' [{subj_name}]' if subj_name else ''
                due = f' Fällig: {_format_date_de(h["due_date"])}' if h.get('due_date') else ''
                lines.append(f'  - {h["title"]}{subj_str}{due}')
            lines.append('')

        upcoming_exams = sorted(
            [e for e in exams if e.get('date', '') >= today],
            key=lambda e: e.get('date', '')
        )[:5]
        if upcoming_exams:
            lines.append('--- Klausuren ---')
            for e in upcoming_exams:
                subj_name = subj_map.get(e.get('subject_id', ''), '')
                lines.append(f'  - {e.get("title", "Klausur")} [{subj_name}] am {_format_date_de(e["date"])}')
            lines.append('')

        upcoming_tests = sorted(
            [t for t in tests if t.get('date', '') >= today],
            key=lambda t: t.get('date', '')
        )[:5]
        if upcoming_tests:
            lines.append('--- Tests ---')
            for t in upcoming_tests:
                subj_name = subj_map.get(t.get('subject_id', ''), '')
                lines.append(f'  - {t.get("title", "Test")} [{subj_name}] am {_format_date_de(t["date"])}')
            lines.append('')

        if grades:
            recent = sorted(grades, key=lambda g: g.get('date', ''), reverse=True)[:10]
            if recent:
                lines.append('--- Letzte Noten ---')
                for g in recent:
                    subj_name = subj_map.get(g.get('subject_id', ''), '')
                    lines.append(f'  - {subj_name}: {g.get("grade_value", "?")} ({_format_date_de(g.get("date", ""))})')
                lines.append('')
    except Exception as ex:
        logging.debug(f'School context error: {ex}')

    # Pomodoro
    try:
        pomo = db.get_pomodoro_stats('week')
        if pomo.get('total_sessions', 0) > 0:
            hours = round((pomo.get('total_minutes', 0) or 0) / 60, 1)
            lines.append('--- Pomodoro (diese Woche) ---')
            lines.append(f'  {pomo["total_sessions"]} Sessions, {hours}h Lernzeit')
            lines.append('')
    except Exception:
        pass

    # Training
    try:
        sessions = db.get_hub_training_sessions(limit=5)
        if sessions:
            lines.append('--- Letzte Trainings ---')
            for s in sessions[:3]:
                dur = f' ({s["duration"]} Min.)' if s.get('duration') else ''
                lines.append(f'  - {s.get("type", "Training")} am {_format_date_de(s.get("date", ""))}{dur}')
            lines.append('')
    except Exception:
        pass

    # Add subject-specific context if message targets a subject
    if message:
        try:
            all_subjects = load_school_fn()[0] if load_school_fn else []
            subj_ctx = _detect_subject_context(message, all_subjects)
            if subj_ctx:
                lines.append(subj_ctx)
        except Exception:
            pass

    return '\n'.join(lines)


def _get_curriculum_context():
    """Build curriculum context from user settings (Bundesland, Klassenstufe, subjects)."""
    settings = db.get_timetable_settings()
    if not settings:
        return ''

    bundesland = settings.get('bundesland', '')
    class_level = settings.get('class_level', 12)

    lines = []
    if bundesland:
        lines.append(f'Bundesland: {bundesland}')
    lines.append(f'Klassenstufe: {class_level}')
    if class_level >= 11:
        lines.append('Kurssystem: Qualifikationsphase (Oberstufe)')
        lines.append('Bewertung: Punkte 0-15 (15=sehr gut, 0=ungenügend)')
    else:
        lines.append('Bewertung: Noten 1-6 (1=sehr gut, 6=ungenügend)')

    return '\n'.join(lines)


def _detect_subject_context(message, subjects):
    """Detect if the user is asking about a specific subject and return relevant context."""
    msg = message.lower()
    subject_aliases = {
        'mathe': ['mathe', 'mathematik', 'rechnen', 'algebra', 'analysis', 'geometrie', 'stochastik',
                   'ableitung', 'integral', 'funktion', 'gleichung', 'vektor', 'matrix'],
        'deutsch': ['deutsch', 'grammatik', 'rechtschreibung', 'aufsatz', 'erörterung', 'gedicht',
                     'interpretation', 'analyse', 'literatur', 'goethe', 'schiller', 'kafka'],
        'englisch': ['englisch', 'english', 'vokabel', 'grammar', 'essay'],
        'physik': ['physik', 'kraft', 'energie', 'geschwindigkeit', 'beschleunigung', 'newton',
                    'elektrizität', 'magnetismus', 'wellen', 'optik', 'thermodynamik'],
        'chemie': ['chemie', 'reaktion', 'element', 'periodensystem', 'mol', 'säure', 'base'],
        'biologie': ['biologie', 'bio', 'zelle', 'genetik', 'evolution', 'ökologie', 'fotosynthese'],
        'geschichte': ['geschichte', 'historisch', 'krieg', 'revolution', 'epoche', 'kaiser', 'weimar'],
        'geografie': ['geografie', 'geographie', 'erdkunde', 'klima', 'kontinent', 'vegetation'],
        'informatik': ['informatik', 'programmier', 'algorithmus', 'datenbank', 'python', 'java'],
        'musik': ['musik', 'harmonielehre', 'komposition', 'rhythmus', 'akkord'],
        'psychologie': ['psychologie', 'psycho', 'verhalten', 'bewusstsein', 'wahrnehmung'],
    }

    detected = None
    for subj_key, keywords in subject_aliases.items():
        if any(kw in msg for kw in keywords):
            detected = subj_key
            break

    if not detected:
        return ''

    # Find the actual subject in user's subjects list
    matched_subject = None
    for s in subjects:
        if detected in s.get('name', '').lower():
            matched_subject = s
            break

    ctx = f'\n--- Fach-Kontext: {detected.capitalize()} ---\n'
    if matched_subject:
        ctx += f'Eingetragenes Fach: {matched_subject.get("name", "")}'
        if matched_subject.get('teacher'):
            ctx += f' (Lehrer: {matched_subject["teacher"]})'
        if matched_subject.get('subject_type'):
            ctx += f', Kursart: {matched_subject["subject_type"]}'
        ctx += '\n'

    return ctx


def build_system_prompt(context):
    curriculum = _get_curriculum_context()
    context = strip_action_markers(context)

    return f"""Du bist der {brand.NAME} Assistent, ein intelligenter Schul- und Produktivitätsassistent.

DEINE FÄHIGKEITEN:
- Du kannst Schulaufgaben lösen und Schritt für Schritt erklären (Mathe, Physik, Deutsch, etc.)
- Du erstellst Lernpläne, Zusammenfassungen und Karteikarten
- Du kennst den Lehrplan und die Anforderungen für die jeweilige Klassenstufe
- Du hilfst bei Textanalyse, Erörterungen, Essays und Interpretationen
- Du analysierst Noten und gibst Verbesserungsvorschläge
- Du planst den Tag und verwaltest Aufgaben
- Du kannst Aufgaben und Termine erstellen

REGELN:
- Antworte IMMER auf Deutsch, freundlich und strukturiert
- Bei Rechenaufgaben: zeige den Lösungsweg Schritt für Schritt
- Bei Textaufgaben: erkläre die Methodik und gib Beispiele
- Beziehe dich auf den {brand.NAME}-Kontext wenn relevant (Noten, Aufgaben, etc.)
- Formatiere übersichtlich mit **Fett** für Wichtiges und Aufzählungen
- Halte Antworten fokussiert; für Mathe-Analysen, Zusammenfassungen, Interpretationen etc. darf die Antwort so lang sein wie nötig
- Für Mathe nutze LaTeX mit $...$ (inline) oder $$...$$ (Block): z.B. $f(x) = 2e^x - 2$, $$\\lim_{{x \\to \\infty}} f(x)$$

FAKTEN-EHRLICHKEIT (sehr wichtig!):
Der {brand.NAME}-Kontext unten kann einen Block "RECHERCHE (automatisch von Wikipedia…)" enthalten. Wenn ja:
→ Schreibe eine VOLLSTÄNDIGE, ausführliche Antwort (mind. 200–400 Wörter bei Personen/Themen) direkt aus dem Recherche-Block.
→ Strukturiere die Antwort sinnvoll: Einleitung, Leben/Karriere chronologisch, wichtige Werke/Leistungen, Bedeutung. Nutze **Fett** und Listen.
→ Paraphrasiere die Fakten, erfinde NICHTS dazu (besonders keine Daten/Zahlen die nicht im Block stehen).
→ Nenne am Ende die Quelle: „Quelle: …".
→ FRAGE NICHT nach „Welcher Bereich interessiert dich?" – liefere direkt die vollständige Zusammenfassung. Nur wenn der Block sehr kurz ist (<200 Wörter Text), erwähne am Ende, dass für Details der Wikipedia-Artikel gelesen werden sollte.
→ Wenn der Block sagt „Kein Artikel gefunden", sag das ehrlich – erfinde keine Biografie.

Wenn KEIN Recherche-Block da ist, gilt: du hast keinen Internet-Zugriff. Erfinde niemals Biografien, Daten, Zitate, Werke, Autoren, Ereignisse oder Statistiken.

ANTWORT-UMFANG (allgemein):
Bei Anfragen wie „Biografie", „Zusammenfassung", „erkläre…", „Infos zu…", „Kurvendiskussion" etc.: liefere die VOLLE Antwort SOFORT beim ersten Turn. Frag nicht nach Details, die du direkt liefern kannst. Nachfrage nur bei echter Mehrdeutigkeit.

• Wenn der Nutzer nach einer PERSON, einem spezifischen Ereignis, einem Werk oder einer konkreten Jahreszahl fragt, die du NICHT mit hoher Sicherheit aus deinem Training kennst:
  → Sag DIREKT: „Diese Person/Dieses Ereignis ist mir nicht zuverlässig bekannt. Ich will dir keine erfundenen Infos geben."
  → Biete stattdessen an, bei der Recherche zu helfen (Wikipedia-Suche, Suchmaschine, Bibliothek).
  → Frage NICHT zuerst nach „Kontext" und erfinde dann doch etwas – das ist schlimmer als ehrliches „Ich weiß es nicht".

• Bei bekannten Fakten (z.B. „Was ist die Hauptstadt von Frankreich?", „Wer schrieb Faust?") antworte normal.

• Bei Unsicherheit IMMER: lieber ehrlich „Ich bin mir nicht sicher" als plausibel klingende Erfindung.

• Platzhalter wie „[Hier müsste…]", „(Bereich X)" oder „Beitrag: Ihre Arbeit in [Bereich X]" sind VERBOTEN. Entweder du weißt es – oder du sagst offen, dass du es nicht weißt.

NIVEAU-ANPASSUNG (wichtig!):
Erkenne am Ton der Frage, WIE VIEL der Nutzer schon weiß und passe DICH an – nicht umgekehrt.

• **Anfänger-Modus** (Signale: „erklär mir", „ich verstehe nicht", „ich hab keine Ahnung", junge Nutzer, offensichtliche Grundlagen-Frage):
  - Starte mit einem Alltags-Bild oder einer Analogie, BEVOR du die Definition bringst.
  - Vermeide Fachbegriffe. Wenn du einen brauchst, erkläre ihn in einem Nebensatz beim ersten Gebrauch.
  - Nutze kleine, konkrete Zahlen-Beispiele statt abstrakter Variablen.
  - Gehe EINEN Schritt, dann pausiere gedanklich: „Macht das bis hier Sinn?"
  - KEINE LaTeX-Formeln ohne Erklärung, was die Symbole bedeuten.

• **Fortgeschrittenen-Modus** (Signale: Klasse 11-13, präzise Fragestellung, Fachvokabular in der Frage):
  - Direkt, präzise, fachlich korrekt.
  - LaTeX, Schrittfolge, Ergebnis.
  - Keine überflüssigen Analogien – der Nutzer will die Lösung, nicht die Motivation.

• **Unsicher?** Frage KURZ nach: „Hast du das Thema schon gehabt, oder fangen wir ganz am Anfang an?" – und dann antworte basierend auf der Antwort.

• Wenn der Nutzer sagt „ich versteh's immer noch nicht", wiederhole NICHT einfach – wechsel die Erklärstrategie (anderes Beispiel, andere Analogie, visuell beschreiben statt formal).

AUFGABEN ERSTELLEN:
NUR wenn der Nutzer explizit eine Aufgabe/einen Termin ERSTELLEN möchte, füge am Ende GENAU diesen Block ein (mit öffnendem UND schließendem Tag):
[ACTION]{{"type": "create_task", "title": "Titel", "due_date": "YYYY-MM-DD", "due_time": "HH:MM", "priority": "medium"}}[/ACTION]
Wenn der Nutzer NICHTS erstellen will (z.B. Mathe-Aufgabe lösen, Frage beantworten), füge KEINEN Action-Block ein.

SCHÜLER-INFO:
{curriculum}

{context}"""


# ---- LLM Backends ----

def _build_local_messages(message, system_prompt, history=None):
    messages = []
    messages.append({'role': 'user', 'content': f'[Kontext und Anweisungen]\n{system_prompt}\n\nBestätige kurz.'})
    messages.append({'role': 'assistant', 'content': f'Verstanden. Ich bin der {brand.NAME} Assistent und helfe dir gerne.'})
    if history:
        messages.extend(history[-4:])
    messages.append({'role': 'user', 'content': message})
    return messages


def _build_server_messages(message, system_prompt, history=None):
    messages = [{'role': 'system', 'content': system_prompt}]
    if history:
        messages.extend(history[-6:])
    messages.append({'role': 'user', 'content': message})
    return messages


def chat_local(message, system_prompt, history=None):
    if local_ai.runtime_installed():
        try:
            return local_ai.server.chat(_build_server_messages(message, system_prompt, history))
        except (local_ai.ServerError, http_requests.RequestException) as e:
            logging.error(f'Local assistant server error: {type(e).__name__}')
            return ''
    llm, model_name = _get_local_llm()
    if not llm:
        return ''

    messages = _build_local_messages(message, system_prompt, history)

    try:
        output = llm.create_chat_completion(
            messages=messages,
            max_tokens=4096,
            temperature=0.7,
            top_p=0.9,
        )
        return output['choices'][0]['message']['content']
    except Exception as e:
        logging.error(f'Local LLM error: {e}')
        return ''


def stream_local(message, system_prompt, history=None):
    if local_ai.runtime_installed():
        try:
            yield from local_ai.server.stream(_build_server_messages(message, system_prompt, history))
        except (local_ai.ServerError, http_requests.RequestException) as e:
            logging.error(f'Local assistant server error: {type(e).__name__}')
        return
    llm, model_name = _get_local_llm()
    if not llm:
        return

    messages = _build_local_messages(message, system_prompt, history)

    try:
        for chunk in llm.create_chat_completion(
            messages=messages,
            max_tokens=4096,
            temperature=0.7,
            top_p=0.9,
            stream=True,
        ):
            delta = chunk['choices'][0].get('delta', {})
            content = delta.get('content', '')
            if content:
                yield content
    except Exception as e:
        logging.error(f'Local LLM stream error: {e}')

def chat_ollama(message, system_prompt, model, history=None):
    messages = [{'role': 'system', 'content': system_prompt}]
    if history:
        messages.extend(history[-10:])
    messages.append({'role': 'user', 'content': message})

    resp = http_requests.post(f'{OLLAMA_BASE}/api/chat', json={
        'model': model,
        'messages': messages,
        'stream': False,
        'options': {'num_predict': 8192, 'num_ctx': 8192},
    }, timeout=240)
    resp.raise_for_status()
    data = resp.json()
    return data.get('message', {}).get('content', '')


def stream_ollama(message, system_prompt, model, history=None):
    messages = [{'role': 'system', 'content': system_prompt}]
    if history:
        messages.extend(history[-10:])
    messages.append({'role': 'user', 'content': message})

    resp = http_requests.post(f'{OLLAMA_BASE}/api/chat', json={
        'model': model,
        'messages': messages,
        'stream': True,
        'options': {'num_predict': 8192, 'num_ctx': 8192},
    }, timeout=300, stream=True)
    resp.raise_for_status()

    for line in resp.iter_lines():
        if line:
            try:
                data = json.loads(line)
                content = data.get('message', {}).get('content', '')
                if content:
                    yield content
                if data.get('done'):
                    break
            except json.JSONDecodeError:
                continue


def chat_claude(message, system_prompt, history=None, tools=None):
    import anthropic
    config = load_config()
    client = anthropic.Anthropic(api_key=config['claude_api_key'])

    messages = []
    if history:
        messages.extend(history[-10:])
    messages.append({'role': 'user', 'content': message})

    kwargs = {
        'model': config.get('claude_model', 'claude-sonnet-4-20250514'),
        'max_tokens': 8192,
        'system': system_prompt,
        'messages': messages,
    }
    if tools:
        kwargs['tools'] = tools

    response = client.messages.create(**kwargs)

    text_parts = []
    tool_uses = []
    for block in response.content:
        if block.type == 'text':
            text_parts.append(block.text)
        elif block.type == 'tool_use':
            tool_uses.append({'name': block.name, 'input': block.input})

    return '\n'.join(text_parts), tool_uses


def stream_claude(message, system_prompt, history=None):
    import anthropic
    config = load_config()
    client = anthropic.Anthropic(api_key=config['claude_api_key'])

    messages = []
    if history:
        messages.extend(history[-10:])
    messages.append({'role': 'user', 'content': message})

    with client.messages.stream(
        model=config.get('claude_model', 'claude-sonnet-4-20250514'),
        max_tokens=8192,
        system=system_prompt,
        messages=messages,
    ) as stream:
        for text in stream.text_stream:
            yield text


# ---- Action Execution ----

def _validate_due_date(raw, today=None):
    """Validate and normalize a due_date from an LLM-emitted action.

    Rejects placeholders, past dates (likely training-cutoff hallucination), and
    malformed strings. Falls back to natural-language parsing for 'morgen' etc.
    Returns a YYYY-MM-DD string or None.
    """
    if not raw or not isinstance(raw, str):
        return None
    s = raw.strip()
    if not s or s.upper() in ('YYYY-MM-DD', 'TBD', 'TBA', 'NULL', 'NONE'):
        return None
    today = today or datetime.now().date()

    m = re.match(r'^(\d{4})-(\d{1,2})-(\d{1,2})$', s)
    if m:
        try:
            d = datetime(int(m.group(1)), int(m.group(2)), int(m.group(3))).date()
            return d.strftime('%Y-%m-%d') if d >= today else None
        except ValueError:
            return None

    m = re.match(r'^(\d{1,2})\.(\d{1,2})\.(\d{2,4})$', s)
    if m:
        day, mo, yr = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if yr < 100:
            yr += 2000
        try:
            d = datetime(yr, mo, day).date()
            return d.strftime('%Y-%m-%d') if d >= today else None
        except ValueError:
            return None

    parsed = _parse_date_nl(s)
    if parsed:
        try:
            d = datetime.strptime(parsed, '%Y-%m-%d').date()
            return parsed if d >= today else None
        except ValueError:
            return None
    return None


def _validate_due_time(raw):
    if not raw or not isinstance(raw, str):
        return None
    s = raw.strip()
    if not s or s.upper() in ('HH:MM', 'TBD', 'NULL', 'NONE'):
        return None
    m = re.match(r'^(\d{1,2}):(\d{2})$', s)
    if not m:
        return None
    h, mi = int(m.group(1)), int(m.group(2))
    if 0 <= h <= 23 and 0 <= mi <= 59:
        return f'{h:02d}:{mi:02d}'
    return None


def execute_action(action, load_school_fn, save_school_fn):
    action_type = action.get('name') or action.get('type', '')
    inp = action.get('input', action)

    if action_type == 'create_task':
        title = inp.get('title', '').strip()
        if not title:
            return {'success': False, 'message': 'Titel fehlt'}
        due_date = _validate_due_date(inp.get('due_date'))
        due_time = _validate_due_time(inp.get('due_time'))
        task_id = db.create_hub_task(
            title=title,
            description=inp.get('description'),
            due_date=due_date,
            due_time=due_time,
            priority=inp.get('priority', 'medium'),
        )
        suffix = ''
        if inp.get('due_date') and not due_date:
            suffix = ' (Datum war ungültig oder vergangen — ohne Fälligkeit angelegt)'
        return {'success': True, 'message': f'Aufgabe "{title}" erstellt{suffix}', 'id': task_id}

    elif action_type == 'complete_task':
        task_id = inp.get('task_id') or inp.get('id')
        title_search = inp.get('title', '').strip()
        if task_id:
            try:
                task = db.get_hub_task(int(task_id))
            except (TypeError, ValueError):
                return {'success': False, 'message': 'Ungültige Task-ID'}
        elif title_search:
            tasks = db.get_hub_tasks('all')
            task = next((t for t in tasks if not t.get('completed') and title_search.lower() in t['title'].lower()), None)
        else:
            return {'success': False, 'message': 'Task-ID oder Titel fehlt'}
        if not task:
            return {'success': False, 'message': 'Aufgabe nicht gefunden'}
        db.toggle_hub_task(task['id'])
        return {'success': True, 'message': f'Aufgabe "{task["title"]}" erledigt ✓'}

    elif action_type == 'delete_task':
        task_id = inp.get('task_id') or inp.get('id')
        if not task_id:
            return {'success': False, 'message': 'Task-ID fehlt'}
        try:
            tid = int(task_id)
        except (TypeError, ValueError):
            return {'success': False, 'message': 'Ungültige Task-ID'}
        task = db.get_hub_task(tid)
        if not task:
            return {'success': False, 'message': 'Aufgabe nicht gefunden'}
        db.delete_hub_task(tid)
        return {'success': True, 'message': f'Aufgabe "{task["title"]}" gelöscht'}

    elif action_type == 'create_homework':
        title = inp.get('title', '').strip()
        if not title:
            return {'success': False, 'message': 'Titel fehlt'}
        homework_list = load_school_fn('homework')
        import uuid
        new_hw = {
            'id': str(uuid.uuid4())[:8],
            'title': title,
            'subject_id': inp.get('subject_id', ''),
            'due_date': inp.get('due_date', ''),
            'description': inp.get('description', ''),
            'completed': False,
            'assigned_date': datetime.now().strftime('%Y-%m-%d'),
        }
        homework_list.append(new_hw)
        save_school_fn('homework', homework_list)
        return {'success': True, 'message': f'Hausaufgabe "{title}" erstellt'}

    elif action_type == 'complete_homework':
        hw_id = inp.get('homework_id') or inp.get('id')
        title_search = inp.get('title', '').strip()
        homework_list = load_school_fn('homework')
        target = None
        for h in homework_list:
            if hw_id and str(h.get('id', '')) == str(hw_id):
                target = h
                break
            if title_search and title_search.lower() in h.get('title', '').lower() and not h.get('completed'):
                target = h
                break
        if not target:
            return {'success': False, 'message': 'Hausaufgabe nicht gefunden'}
        target['completed'] = True
        save_school_fn('homework', homework_list)
        return {'success': True, 'message': f'Hausaufgabe "{target["title"]}" erledigt ✓'}

    return {'success': False, 'message': f'Unbekannte Aktion: {action_type}'}


def extract_ollama_actions(response_text):
    actions = []
    cleaned = response_text

    pattern_closed = r'\[ACTION\](.*?)\[/ACTION\]'
    for match in re.findall(pattern_closed, cleaned, re.DOTALL):
        try:
            actions.append(json.loads(match.strip()))
        except json.JSONDecodeError:
            continue
    cleaned = re.sub(pattern_closed, '', cleaned, flags=re.DOTALL)

    marker = '[ACTION]'
    out = []
    i = 0
    while i < len(cleaned):
        if cleaned.startswith(marker, i):
            j = i + len(marker)
            while j < len(cleaned) and cleaned[j] in ' \t\r\n':
                j += 1
            if j < len(cleaned) and cleaned[j] == '{':
                depth = 0
                in_str = False
                esc = False
                end = -1
                for k in range(j, len(cleaned)):
                    c = cleaned[k]
                    if esc:
                        esc = False
                        continue
                    if c == '\\':
                        esc = True
                        continue
                    if c == '"':
                        in_str = not in_str
                    elif not in_str:
                        if c == '{':
                            depth += 1
                        elif c == '}':
                            depth -= 1
                            if depth == 0:
                                end = k
                                break
                if end != -1:
                    try:
                        actions.append(json.loads(cleaned[j:end + 1]))
                    except json.JSONDecodeError:
                        pass
                    i = end + 1
                    continue
            i += len(marker)
            continue
        out.append(cleaned[i])
        i += 1
    cleaned = ''.join(out)

    orphan_sep = re.search(r'\n*-{2,}\s*\n+\s*(\{[\s\S]*?("type"|"name"|"title")[\s\S]*)$', cleaned)
    orphan_plain = re.search(r'\n+\s*(\{\s*"(?:type|name|title)"\s*:[\s\S]*)$', cleaned)
    orphan = orphan_sep or orphan_plain
    if orphan:
        blob = orphan.group(1)
        brace_start = blob.find('{')
        if brace_start != -1:
            # Try to extract a balanced JSON object; if incomplete, just drop the fragment.
            depth = 0
            in_str = False
            esc = False
            end = -1
            for k in range(brace_start, len(blob)):
                c = blob[k]
                if esc:
                    esc = False
                    continue
                if c == '\\':
                    esc = True
                    continue
                if c == '"':
                    in_str = not in_str
                elif not in_str:
                    if c == '{':
                        depth += 1
                    elif c == '}':
                        depth -= 1
                        if depth == 0:
                            end = k
                            break
            if end != -1:
                try:
                    actions.append(json.loads(blob[brace_start:end + 1]))
                except json.JSONDecodeError:
                    pass
        cleaned = cleaned[:orphan.start()]
    return cleaned.strip(), actions


# ---- Natural Language Task/Event Parsing ----

def _parse_date_nl(text, reference_date=None):
    """Parse natural language date references into YYYY-MM-DD."""
    now = reference_date or datetime.now()
    today = now.date()
    t = text.lower()

    if 'heute' in t or 'today' in t:
        return today.strftime('%Y-%m-%d')
    if 'morgen' in t or 'tomorrow' in t:
        return (today + timedelta(days=1)).strftime('%Y-%m-%d')
    if 'übermorgen' in t:
        return (today + timedelta(days=2)).strftime('%Y-%m-%d')

    # "am Montag", "nächsten Dienstag", etc.
    for i, name in enumerate(DAY_NAMES_DE):
        if name.lower() in t:
            current_weekday = today.weekday()
            diff = (i - current_weekday) % 7
            if diff == 0:
                diff = 7  # next week if same day
            return (today + timedelta(days=diff)).strftime('%Y-%m-%d')

    # "in X Tagen"
    m = re.search(r'in\s+(\d+)\s+tag', t)
    if m:
        return (today + timedelta(days=int(m.group(1)))).strftime('%Y-%m-%d')

    # Explicit dates: "am 15.4", "15.04.", "15. April"
    month_names = {'januar': 1, 'februar': 2, 'märz': 3, 'april': 4, 'mai': 5, 'juni': 6,
                   'juli': 7, 'august': 8, 'september': 9, 'oktober': 10, 'november': 11, 'dezember': 12}
    m = re.search(r'(\d{1,2})\.\s*(\d{1,2})\.?', t)
    if m:
        day, month = int(m.group(1)), int(m.group(2))
        year = today.year
        try:
            d = datetime(year, month, day).date()
            if d < today:
                d = datetime(year + 1, month, day).date()
            return d.strftime('%Y-%m-%d')
        except ValueError:
            pass

    for mname, mnum in month_names.items():
        m = re.search(rf'(\d{{1,2}})\.\s*{mname}', t)
        if m:
            try:
                d = datetime(today.year, mnum, int(m.group(1))).date()
                if d < today:
                    d = datetime(today.year + 1, mnum, int(m.group(1))).date()
                return d.strftime('%Y-%m-%d')
            except ValueError:
                pass

    return None


def _parse_time_nl(text):
    """Parse natural language time references into HH:MM."""
    t = text.lower()

    # "um 15:00", "um 3pm", "um 15 Uhr"
    m = re.search(r'um\s+(\d{1,2})[:\.](\d{2})', t)
    if m:
        return f'{int(m.group(1)):02d}:{m.group(2)}'

    m = re.search(r'um\s+(\d{1,2})\s*uhr', t)
    if m:
        return f'{int(m.group(1)):02d}:00'

    m = re.search(r'at\s+(\d{1,2})[:\.](\d{2})', t)
    if m:
        return f'{int(m.group(1)):02d}:{m.group(2)}'

    m = re.search(r'at\s+(\d{1,2})\s*(pm|am)', t)
    if m:
        hour = int(m.group(1))
        if m.group(2) == 'pm' and hour < 12:
            hour += 12
        return f'{hour:02d}:00'

    m = re.search(r'(\d{1,2})[:\.](\d{2})\s*uhr', t)
    if m:
        return f'{int(m.group(1)):02d}:{m.group(2)}'

    return None


def _extract_title_from_nl(text):
    """Extract the task/event title from a natural language creation request."""
    t = text.strip()

    # Remove common prefixes
    prefixes = [
        r'^(erstell|erstelle|create|add|neue?s?)\s+(eine?\s+)?(aufgabe|task|termin|event|erinnerung|reminder)\s*:?\s*',
        r'^(erinnere?\s+mich\s+(an\s+)?)',
        r'^(ich\s+muss\s+)',
        r'^(task|aufgabe|termin)\s*:?\s*',
        r'^(trag\s+ein\s*:?\s*)',
        r'^(add\s+)',
    ]
    title = t
    for prefix in prefixes:
        title = re.sub(prefix, '', title, flags=re.IGNORECASE).strip()

    # Remove date/time suffixes
    suffixes = [
        r'\s+(heute|morgen|übermorgen|tomorrow|today).*$',
        r'\s+am\s+\d{1,2}\.\s*\d{1,2}\.?.*$',
        r'\s+am\s+(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag).*$',
        r'\s+um\s+\d{1,2}[:.]\d{2}.*$',
        r'\s+um\s+\d{1,2}\s*uhr.*$',
        r'\s+at\s+\d{1,2}.*$',
        r'\s+in\s+\d+\s+tag.*$',
        r'\s+bis\s+(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag).*$',
        r'\s+bis\s+\d{1,2}\.\s*\d{1,2}\.?.*$',
    ]
    for suffix in suffixes:
        title = re.sub(suffix, '', title, flags=re.IGNORECASE).strip()

    # Clean up
    title = title.strip(' .,;:!?')
    return title if title else None


def _kw_match(msg, keywords, word_boundary=False):
    if word_boundary:
        for kw in keywords:
            if re.search(r'(?<!\w)' + re.escape(kw) + r'(?!\w)', msg, re.IGNORECASE):
                return True
        return False
    return any(kw in msg for kw in keywords)


def _detect_creation_intent(message):
    msg = message.lower().strip()
    creation_keywords = [
        'erstell', 'erstelle', 'create', 'neue aufgabe', 'neuer termin',
        'erinnere mich', 'remind me', 'trag ein', 'ich muss', 'nicht vergessen',
        'aufgabe:', 'task:', 'termin:', 'todo:',
    ]
    if any(kw in msg for kw in creation_keywords):
        return True
    return bool(re.search(r'(?<!\w)add(?!\w)', msg))


def try_create_from_nl(message, load_school_fn=None, save_school_fn=None):
    """Try to parse and create a task from natural language. Returns (success, response_text)."""
    title = _extract_title_from_nl(message)
    if not title or len(title) < 2:
        return False, None

    due_date = _parse_date_nl(message)
    due_time = _parse_time_nl(message)

    # Determine priority from keywords
    msg_lower = message.lower()
    priority = 'medium'
    if any(w in msg_lower for w in ['wichtig', 'dringend', 'urgent', 'important', 'asap']):
        priority = 'high'
    elif any(w in msg_lower for w in ['irgendwann', 'niedrig', 'low', 'optional']):
        priority = 'low'

    # Create the task
    db.create_hub_task(
        title=title,
        due_date=due_date,
        due_time=due_time,
        priority=priority,
    )

    # Build confirmation
    parts = [f'**Aufgabe erstellt:** "{title}"']
    if due_date:
        parts.append(f'Fällig: {_format_date_de(due_date)}')
    if due_time:
        parts.append(f'um {due_time} Uhr')
    if priority != 'medium':
        prio_de = {'high': 'Hoch', 'low': 'Niedrig'}
        parts.append(f'Priorität: {prio_de.get(priority, priority)}')

    return True, '\n'.join(parts)


def is_data_query(message):
    msg = message.lower().strip()

    if len(msg) > 400:
        return False
    if re.search(r'fasse\b[\s\S]+\bzusammen', msg):
        return False

    substring_patterns = [
        'was steht an', 'tagesübersicht', 'mein tag', 'tagesplan',
        'diese woche', 'wochenübersicht',
        'stundenplan', 'unterricht', 'welche fächer', 'welche stunden',
        'offene aufgaben', 'tasks', 'todo',
        'überfällig', 'overdue',
        'hausaufgabe', 'homework',
        'klausur', 'prüfung',
        'noten', 'durchschnitt', 'notenanalyse',
        'karteikarte', 'flashcard',
        'deadline', 'countdown',
        'produktivität', 'statistik',
        'training', 'pomodoro',
        'motivation', 'gestresst', 'keine lust',
        'vorschlag', 'empfehlung',
        'erledigt', 'fertig', 'abhaken',
        'ha erledigt', 'ha fertig',
        'lernplan',
        'notentipps', 'noten verbessern',
        'erörterung', 'interpretation', 'zusammenfass', 'aufsatz',
        'was kannst du',
    ]
    boundary_patterns = [
        'test', 'tests', 'exam', 'exams', 'quiz', 'stats', 'tipp', 'tipps',
        'tip', 'review', 'hilfe', 'help', 'überblick',
        'hallo', 'hi', 'hey', 'moin',
    ]

    if _detect_creation_intent(message):
        return True
    if _kw_match(msg, substring_patterns):
        return True
    if re.search(r'was\s+steht\s+(?:heute\s+)?an', msg):
        return True
    return _kw_match(msg, boundary_patterns, word_boundary=True)


# ---- Offline Fallback (Data-Driven) ----

def offline_response(message, load_school_fn=None):
    msg = message.lower().strip()
    now = datetime.now()
    today = now.strftime('%Y-%m-%d')
    weekday = now.weekday()

    # Injection / code payloads: don't route through intent matching; admit unknown.
    if (re.search(r'\b(?:drop|delete|update|select|insert|alter|truncate)\s+(?:table|from|into)\b', msg)
            or '<script' in msg
            or '__import__' in message
            or 'eval(' in msg and 'import' in msg):
        return ('Ich konnte deine Frage gerade nicht beantworten – sie sah nicht '
                'wie eine natürliche Frage aus. Versuch es bitte nochmal oder '
                'formuliere anders.')

    from . import offline_tools
    tool_answer = offline_tools.try_offline_tool(message)
    if tool_answer:
        return tool_answer

    from . import curriculum_service
    curr_answer = curriculum_service.try_curriculum(message)
    if curr_answer:
        return curr_answer

    if re.search(r'fasse\b[\s\S]+\bzusammen', msg) or 'zusammenfass' in msg:
        return _build_text_help(msg, message)

    # ---- Task/Event Creation ----
    if _detect_creation_intent(message):
        success, response = try_create_from_nl(message)
        if success:
            return response

    # ---- Task Completion ----
    if any(w in msg for w in ['erledigt', 'fertig', 'done', 'abhaken', 'geschafft', 'abgehakt']):
        return _try_complete_task(message)

    # ---- Homework Completion ----
    if any(w in msg for w in ['hausaufgabe erledigt', 'ha fertig', 'ha erledigt', 'hausaufgabe fertig',
                               'homework done', 'ha gemacht']):
        return _try_complete_homework(message, load_school_fn)

    # ---- Flashcards / Karteikarten ----
    if any(w in msg for w in ['karteikarte', 'flashcard', 'lernkarte', 'abfragen', 'quiz']):
        return _build_flashcards(msg, load_school_fn)

    # ---- Grade Analysis (before text analysis, since "analyse" overlaps) ----
    if any(w in msg for w in ['notenanalyse', 'notentipps', 'wie verbessere ich', 'schlechte note',
                               'was muss ich für', 'noten verbessern', 'abi-schnitt', 'abitur prognose']):
        return _build_grade_analysis(load_school_fn)

    # ---- Text Analysis ----
    if any(w in msg for w in ['zusammenfass', 'korrigier', 'verbessere text', 'formulier',
                               'erörterung', 'interpretation', 'gedichtanalyse', 'textanalyse',
                               'essay', 'aufsatz']):
        return _build_text_help(msg, message)

    # ---- Motivation / Encouragement ----
    if any(w in msg for w in ['motivation', 'motivier', 'keine lust', 'gestresst', 'stress',
                               'überfordert', 'schaffe das nicht', 'aufmuntern']):
        return _build_motivation(load_school_fn)

    # ---- Deadlines / Countdown ----
    if any(w in msg for w in ['deadline', 'frist', 'countdown', 'wie viel zeit', 'wann ist']):
        return _build_deadline_countdown(load_school_fn, today)

    # ---- Smart Daily Tip ----
    if (_kw_match(msg, ['tipp', 'tipps', 'tip', 'rat', 'rats'], word_boundary=True)
            or 'vorschlag' in msg or 'empfehlung' in msg or 'was soll ich' in msg):
        return _build_smart_tip(load_school_fn, today, weekday, now)

    # ---- Productivity Stats ----
    if ('produktivität' in msg or 'statistik' in msg or 'wie produktiv' in msg or 'fortschritt' in msg
            or _kw_match(msg, ['stats'], word_boundary=True)):
        return _build_productivity_stats()

    # ---- Tagesübersicht / Was steht an ----
    if (any(w in msg for w in ['tagesübersicht', 'überblick', 'zusammenfassung', 'was habe ich heute',
                                'was muss ich', 'mein tag', 'tagesplan'])
            or re.search(r'was\s+steht\s+(?:heute\s+)?an', msg)):
        return _build_day_summary(today, weekday, now, load_school_fn)

    if ('diese woche' in msg or 'wochenübersicht' in msg or 'wochenuebersicht' in msg
            or re.search(r'\b(?:woche|wochenplan)\b', msg)):
        return _build_week_summary(today, now, load_school_fn)

    # ---- Stundenplan ----
    if any(w in msg for w in ['stundenplan', 'unterricht', 'welche fächer', 'welche stunden', 'schule heute']):
        return _build_timetable_response(weekday, now, msg)

    # ---- Aufgaben / Tasks ----
    if ('aufgaben' in msg or 'offene aufgaben' in msg
            or _kw_match(msg, ['tasks', 'todo', 'to-do', 'todos'], word_boundary=True)):
        return _build_tasks_response()

    if any(w in msg for w in ['überfällig', 'overdue', 'verpasst']):
        tasks = db.get_hub_tasks('overdue')
        if not tasks:
            return 'Keine überfälligen Aufgaben – alles im grünen Bereich!'
        lines = ['⚠ **Überfällige Aufgaben:**']
        for t in tasks[:10]:
            due = _format_date_de(t['due_date']) if t.get('due_date') else ''
            lines.append(f'  • {t["title"]} (fällig: {due})')
        return '\n'.join(lines)

    # ---- Hausaufgaben ----
    if any(w in msg for w in ['hausaufgabe', 'homework', 'ha ', 'aufgegeben']):
        return _build_homework_response(load_school_fn, today)

    # ---- Klausuren / Tests ----
    if ('klausur' in msg or 'prüfung' in msg or 'arbeit schreib' in msg
            or _kw_match(msg, ['test', 'tests', 'exam', 'exams'], word_boundary=True)):
        return _build_exams_response(load_school_fn, today)

    # ---- Noten ----
    if any(w in msg for w in ['note', 'noten', 'durchschnitt', 'schnitt', 'grade', 'punkte']):
        return _build_grades_response(load_school_fn)

    # ---- Lernplan ----
    if any(w in msg for w in ['lernplan', 'lernen', 'study plan', 'vorbereiten', 'vorbereitung']):
        return _build_study_plan(load_school_fn, today, msg)

    # ---- Training ----
    if any(w in msg for w in ['training', 'workout', 'sport', 'fitness']):
        return _build_training_response()

    # ---- Pomodoro ----
    if any(w in msg for w in ['pomodoro', 'lernzeit', 'studienzeit', 'wie viel gelernt']):
        return _build_pomodoro_response()

    # ---- Reviews ----
    if any(w in msg for w in ['review', 'reflexion', 'tagebuch', 'journal']):
        return _build_review_response()

    # ---- Hilfe ----
    if any(w in msg for w in ['hilfe', 'was kannst du', 'help', 'funktionen', 'befehle']):
        return (f'Ich bin der **{brand.NAME} Assistent**! Hier ist alles, was ich kann:\n\n'
                '**Organisation:**\n'
                '  • "Was steht heute an?" – Tagesübersicht\n'
                '  • "Wochenübersicht" – Die ganze Woche\n'
                '  • "Stundenplan" / "Stundenplan Montag" – Unterricht\n'
                '  • "Deadlines" – Countdown aller Fristen\n\n'
                '**Aufgaben:**\n'
                '  • "Neue Aufgabe: Einkaufen morgen um 15 Uhr" – Erstellen\n'
                '  • "Erledigt: Einkaufen" – Aufgabe abhaken\n'
                '  • "Offene Aufgaben" – Alle Tasks nach Priorität\n'
                '  • "Überfällige" – Verpasste Aufgaben\n\n'
                '**Schule:**\n'
                '  • "Hausaufgaben" / "HA erledigt: Mathe" – Anzeigen/Abhaken\n'
                '  • "Klausuren" – Alle Prüfungen mit Countdown\n'
                '  • "Noten" – Übersicht pro Fach\n'
                '  • "Notenanalyse" – Detaillierte Tipps zur Verbesserung\n'
                '  • "Lernplan für Mathe" – Personalisierter Plan\n\n'
                '**Lernen:**\n'
                '  • "Karteikarten Physik" – Lernkarten generieren\n'
                '  • "Erörterung" – Textform-Anleitungen\n'
                '  • "Interpretation" – Gedichtanalyse-Guide\n'
                '  • Jede Frage zu Schulfächern (Mathe, Physik, Deutsch...)\n\n'
                '**Insights:**\n'
                '  • "Statistik" / "Produktivität" – Dein Dashboard\n'
                '  • "Tipp" – Smarte Empfehlungen\n'
                '  • "Motivation" – Aufmunterung & Tipps\n\n'
                '**Sonstiges:**\n'
                '  • "Training" / "Pomodoro" / "Reviews"')

    # ---- Greeting / Smalltalk ----
    if (_kw_match(msg, ['hallo', 'hi', 'hey', 'moin'], word_boundary=True)
            or 'guten morgen' in msg or 'guten tag' in msg or 'guten abend' in msg):
        greeting = 'Guten Morgen' if now.hour < 12 else 'Guten Tag' if now.hour < 18 else 'Guten Abend'
        tasks = db.get_hub_tasks('today')
        open_count = len([t for t in tasks if not t.get('completed')])
        extra = f' Du hast {open_count} offene Aufgaben für heute.' if open_count else ' Keine Aufgaben für heute – entspann dich!'
        return f'{greeting}!{extra} Frag mich gerne, was du wissen möchtest.'

    from . import research_service
    if research_service.wants_research(message):
        entity = research_service.extract_entity(message)
        result = research_service.wikipedia_summary(entity) if entity else None
        if result:
            disamb = ' *(Begriffsklärung – mehrere Bedeutungen)*' if result.get('disambiguation') else ''
            src = f'\n\nQuelle: {result["url"]}' if result.get('url') else ''
            return f'**{result["title"]}**{disamb}\n\n{result["extract"]}{src}'
        if entity:
            return (f'Ich konnte zu **"{entity}"** keinen Wikipedia-Eintrag finden und habe '
                    f'gerade keine andere Quelle. Prüfe bitte die Schreibweise oder '
                    f'gib mir mehr Kontext.')

    return (
        "Ich konnte deine Frage gerade nicht beantworten – die KI im Hintergrund "
        "hat keine Antwort geliefert und es gibt auch keine passende Vorlage dafür. "
        "Versuch es bitte nochmal oder formuliere die Frage anders."
    )


# ---- New Feature Handlers ----

def _try_complete_task(message):
    """Try to mark a task as complete from natural language."""
    msg = message.lower()
    tasks = db.get_hub_tasks('all')
    open_tasks = [t for t in tasks if not t.get('completed')]

    if not open_tasks:
        return 'Keine offenen Aufgaben zum Abhaken.'

    # Try to find the task by name match
    best_match = None
    best_score = 0
    # Remove common prefixes
    clean = re.sub(r'^(aufgabe\s+|task\s+)?(erledigt|fertig|done|abhaken|geschafft)\s*:?\s*', '', msg).strip()
    clean = re.sub(r'\s+(erledigt|fertig|done|abhaken|geschafft)$', '', clean).strip()

    for t in open_tasks:
        title_lower = t['title'].lower()
        if clean and clean in title_lower:
            score = len(clean) / len(title_lower)
            if score > best_score:
                best_score = score
                best_match = t
        elif title_lower in msg:
            best_match = t
            best_score = 1.0

    if best_match and best_score > 0.3:
        db.toggle_hub_task(best_match['id'])
        return f'**Aufgabe erledigt** ✓\n"{best_match["title"]}" wurde als erledigt markiert.'

    # Show list to pick from
    lines = ['Welche Aufgabe möchtest du abhaken?\n']
    for i, t in enumerate(open_tasks[:10], 1):
        due = f' ({_format_date_de(t["due_date"])})' if t.get('due_date') else ''
        lines.append(f'  {i}. {t["title"]}{due}')
    lines.append('\nSag z.B. "Erledigt: Einkaufen"')
    return '\n'.join(lines)


def _try_complete_homework(message, load_school_fn):
    """Try to mark homework as complete."""
    if not load_school_fn:
        return 'Keine Schuldaten verfügbar.'
    try:
        subjects, homework, _, _, _ = load_school_fn()
        subj_map = {s.get('id', ''): s.get('name', '') for s in subjects}
        open_hw = [h for h in homework if not h.get('completed')]
        if not open_hw:
            return 'Keine offenen Hausaufgaben – alles erledigt!'

        msg = message.lower()
        clean = re.sub(r'^(hausaufgabe|ha)\s*(erledigt|fertig|done|gemacht)\s*:?\s*', '', msg).strip()

        for h in open_hw:
            if clean and clean in h.get('title', '').lower():
                h['completed'] = True
                from .crypto_utils import encrypt_file
                SCHOOL_HOMEWORK_FILE = DATA_DIR / 'school_homework.json'
                encrypt_file(homework, SCHOOL_HOMEWORK_FILE)
                return f'**Hausaufgabe erledigt** ✓\n"{h["title"]}" abgehakt.'

        lines = ['Welche Hausaufgabe ist erledigt?\n']
        for h in open_hw[:8]:
            subj = subj_map.get(h.get('subject_id', ''), '')
            lines.append(f'  • {h["title"]}{" [" + subj + "]" if subj else ""}')
        lines.append('\nSag z.B. "HA erledigt: Mathe S.45"')
        return '\n'.join(lines)
    except Exception:
        return 'Fehler beim Laden der Hausaufgaben.'


def _build_flashcards(msg, load_school_fn):
    """Generate flashcard-style Q&A for study topics."""
    # Detect subject
    subject = None
    topics_map = {
        'mathe': [
            ('Was ist die Ableitung von x^n?', 'f\'(x) = n · x^(n-1) (Potenzregel)'),
            ('Was ist die Kettenregel?', 'f\'(g(x)) = f\'(g(x)) · g\'(x) — äußere Ableitung mal innere Ableitung'),
            ('Was ist die Produktregel?', '(u·v)\' = u\'·v + u·v\''),
            ('Was ist eine e-Funktion?', 'f(x) = e^x, Besonderheit: f\'(x) = e^x (Ableitung = Funktion)'),
            ('Was bedeutet Monotonie?', 'f\'(x) > 0 → monoton steigend, f\'(x) < 0 → monoton fallend'),
            ('Was ist ein Wendepunkt?', 'f\'\'(x) = 0 und f\'\'\'(x) ≠ 0 — Krümmung wechselt'),
            ('Was ist eine Stammfunktion?', 'F(x) mit F\'(x) = f(x), z.B. ∫x² dx = x³/3 + C'),
            ('Was ist die Wahrscheinlichkeit von A∪B?', 'P(A∪B) = P(A) + P(B) - P(A∩B)'),
        ],
        'deutsch': [
            ('Was ist eine Erörterung?', 'Argumentativer Text: Einleitung → These → Argumente (Pro/Contra) → Fazit'),
            ('Was ist eine Textanalyse?', 'Einleitung (Autor, Titel, Textart, Thema) → Inhalt → Sprache → Deutung'),
            ('Was sind rhetorische Mittel?', 'Metapher, Alliteration, Anapher, Hyperbel, Ironie, Parallelismus...'),
            ('Was ist ein Epochenmerkmal der Romantik?', 'Sehnsucht, Natur, Gefühl, blaue Blume, Nacht, Traum, Wandern'),
            ('Was ist der Unterschied Epik/Lyrik/Dramatik?', 'Epik: erzählend, Lyrik: Gedichte/Verse, Dramatik: Dialog/Bühne'),
            ('Wie ist ein Gedicht aufgebaut?', 'Strophen → Verse → Reimschema (Paarreim, Kreuzreim) → Metrum'),
        ],
        'physik': [
            ('Was besagt F = m·a?', 'Kraft = Masse × Beschleunigung (2. Newtonsches Gesetz)'),
            ('Was ist kinetische Energie?', 'E_kin = ½·m·v² — Energie durch Bewegung'),
            ('Was ist der Energieerhaltungssatz?', 'Energie kann nicht erzeugt oder vernichtet werden, nur umgewandelt'),
            ('Was ist Ohms Gesetz?', 'U = R·I — Spannung = Widerstand × Stromstärke'),
            ('Was ist Leistung?', 'P = W/t = U·I — Arbeit pro Zeit (Watt)'),
        ],
        'geschichte': [
            ('Wann war die Französische Revolution?', '1789–1799, Sturm auf die Bastille am 14. Juli 1789'),
            ('Was war die Weimarer Republik?', 'Erste deutsche Demokratie 1918–1933, endete mit Machtergreifung Hitlers'),
            ('Was war der Kalte Krieg?', '1947–1991, Systemkonflikt USA (Kapitalismus) vs. UdSSR (Kommunismus)'),
            ('Was war der Mauerfall?', '9. November 1989, Fall der Berliner Mauer → Deutsche Wiedervereinigung 1990'),
        ],
        'englisch': [
            ('Present Perfect vs Simple Past?', 'Present Perfect: Bezug zur Gegenwart (have done). Simple Past: abgeschlossen (did)'),
            ('Was sind Conditional Sentences?', 'If + Present → will (Type 1), If + Past → would (Type 2), If + Past Perfect → would have (Type 3)'),
            ('Was ist ein Topic Sentence?', 'Erster Satz eines Absatzes, fasst die Hauptidee zusammen'),
        ],
    }

    for subj, _cards in topics_map.items():
        if subj in msg:
            subject = subj
            break

    if not subject:
        # Try to match user's subjects
        if load_school_fn:
            try:
                subjects = load_school_fn()[0]
                for s in subjects:
                    sname = s.get('name', '').lower()
                    for key in topics_map:
                        if key in sname:
                            if key in msg or sname in msg:
                                subject = key
                                break
                    if subject:
                        break
            except Exception:
                pass

    if subject and subject in topics_map:
        cards = topics_map[subject]
        import random
        selected = random.sample(cards, min(4, len(cards)))
        lines = [f'**Karteikarten: {subject.capitalize()}**\n']
        for i, (q, a) in enumerate(selected, 1):
            lines.append(f'**Frage {i}:** {q}')
            lines.append(f'**Antwort:** {a}\n')
        lines.append('💡 Frag nach einem anderen Fach oder sag "Quiz Mathe" für neue Karten.')
        return '\n'.join(lines)

    available = ', '.join(k.capitalize() for k in topics_map.keys())
    return f'**Karteikarten** – verfügbar für: {available}\n\nSag z.B. "Karteikarten Mathe" oder "Quiz Physik".'


def _build_text_help(msg, original_message):
    """Provide text analysis / writing help."""
    if 'zusammenfass' in msg or re.search(r'fasse\b[\s\S]+\bzusammen', msg):
        return ('**Zusammenfassung erstellen – So geht\'s:**\n\n'
                '1. **Einleitungssatz:** Autor, Titel, Textart, Erscheinungsjahr, Thema\n'
                '2. **Hauptteil:** Wichtigste Aussagen in eigenen Worten, chronologisch\n'
                '3. **Regeln:** Präsens, keine wörtliche Rede, keine eigene Meinung, sachlich\n'
                '4. **Länge:** Ca. 1/3 des Originaltexts\n\n'
                '💡 Für eine echte Zusammenfassung deines Texts wird ein KI-Backend (Ollama/Claude) benötigt.')

    if 'erörterung' in msg or 'essay' in msg or 'aufsatz' in msg:
        return ('**Erörterung / Essay schreiben:**\n\n'
                '**Dialektische Erörterung (Pro/Contra):**\n'
                '1. **Einleitung:** Aktueller Bezug → Hinführung → Fragestellung\n'
                '2. **Hauptteil:**\n'
                '   • Schwächstes Gegenargument (mit Beispiel)\n'
                '   • Stärkstes Gegenargument\n'
                '   • Schwächstes eigenes Argument\n'
                '   • Stärkstes eigenes Argument (Sanduhr-Prinzip)\n'
                '3. **Schluss:** Fazit, eigene Position, Ausblick\n\n'
                '**Lineare Erörterung (nur eine Seite):**\n'
                '1. Einleitung → 2. Argumente (schwach→stark) → 3. Fazit\n\n'
                '**Sprachliche Tipps:**\n'
                '  • Konjunktionen: erstens, darüber hinaus, jedoch, abschließend\n'
                '  • Sachlicher Stil, keine Umgangssprache\n'
                '  • Jedes Argument: Behauptung → Begründung → Beispiel')

    if 'interpretation' in msg or 'gedicht' in msg:
        return ('**Gedichtinterpretation:**\n\n'
                '1. **Einleitung:** Titel, Autor, Epoche, Thema, Deutungshypothese\n'
                '2. **Analyse (strophenweise):**\n'
                '   • Inhalt: Was wird gesagt?\n'
                '   • Form: Reimschema, Metrum, Enjambement\n'
                '   • Sprache: Stilmittel (Metapher, Vergleich, Alliteration...)\n'
                '   • Wirkung: Welchen Effekt hat das?\n'
                '3. **Schluss:** Deutungshypothese bestätigen/widerlegen, Epochenzuordnung\n\n'
                '💡 Tipp: Immer Inhalt, Form und Sprache verknüpfen!')

    if 'korrigier' in msg or 'verbessere' in msg or 'formulier' in msg:
        return ('**Textverbesserung** – Schick mir deinen Text und ich helfe dir!\n\n'
                'Die KI kann:\n'
                '  • Grammatik und Rechtschreibung prüfen\n'
                '  • Stil verbessern (sachlicher, wissenschaftlicher)\n'
                '  • Formulierungen optimieren\n'
                '  • Struktur vorschlagen\n\n'
                'Schreib einfach deinen Text in die nächste Nachricht.')

    return ('**Texthilfe** – Ich kann dir helfen bei:\n\n'
            '  • "Zusammenfassung" – Wie man zusammenfasst\n'
            '  • "Erörterung" – Aufbau und Tipps\n'
            '  • "Interpretation" – Gedicht-/Textanalyse\n'
            '  • "Korrigiere..." – Text verbessern (mit KI)\n\n'
            'Sag mir, wobei du Hilfe brauchst!')


def _build_grade_analysis(load_school_fn):
    """Detailed grade analysis with improvement tips."""
    if not load_school_fn:
        return 'Keine Schuldaten verfügbar.'
    try:
        subjects, _, _, _, grades = load_school_fn()
        if not grades:
            return 'Noch keine Noten eingetragen.'

        subj_map = {s.get('id', ''): s for s in subjects}
        by_subj = {}
        for g in grades:
            sid = g.get('subject_id', '')
            if sid not in by_subj:
                by_subj[sid] = []
            by_subj[sid].append({
                'value': g.get('points', g.get('grade_value', 0)),
                'date': g.get('date', ''),
                'type': g.get('type', ''),
            })

        lines = ['**Notenanalyse mit Empfehlungen:**\n']

        # Sort by average (worst first)
        subj_stats = []
        for sid, grade_list in by_subj.items():
            values = [g['value'] for g in grade_list]
            avg = sum(values) / len(values)
            recent = values[-2:] if len(values) >= 2 else values
            recent_avg = sum(recent) / len(recent)
            trend = recent_avg - avg
            subj_stats.append((sid, avg, trend, values, grade_list))

        subj_stats.sort(key=lambda x: x[1])  # worst first

        for sid, avg, trend, _values, _grade_list in subj_stats:
            subj = subj_map.get(sid, {})
            name = subj.get('name', sid)
            stype = subj.get('subject_type', '')
            weight = ' (LK – doppelt gewichtet!)' if stype == 'LK' else ''

            trend_str = '↗' if trend > 0.5 else '↘' if trend < -0.5 else '→'

            lines.append(f'**{name}** – Ø {avg:.1f} {trend_str}{weight}')

            # Specific advice
            if avg < 5:
                lines.append('  ⚠ Kritisch! Dringend Nachhilfe oder Lehrergespräch empfohlen.')
            elif avg < 8:
                lines.append('  → Regelmäßig lernen, Übungsaufgaben machen, mündlich mehr beteiligen.')
            elif avg < 11:
                lines.append('  → Solide Basis. Fokus auf Klausurvorbereitung und mündliche Mitarbeit.')
            elif avg < 14:
                lines.append('  → Gutes Niveau! Details und Vertiefungen können noch Punkte bringen.')
            else:
                lines.append('  ✓ Sehr gut! Weiter so.')

            if trend < -1:
                lines.append('  📉 Negativer Trend – letzte Noten schwächer als Durchschnitt.')
            elif trend > 1:
                lines.append('  📈 Positiver Trend – du verbesserst dich!')

            lines.append('')

        # Overall
        all_values = [g.get('points', g.get('grade_value', 0)) for g in grades]
        overall = sum(all_values) / len(all_values)
        lines.append(f'**Gesamtschnitt: {overall:.1f} Punkte**')

        if overall >= 13:
            lines.append('🌟 Sehr gut! Abitur-Prognose: ~1,0-1,3')
        elif overall >= 11:
            lines.append('✓ Gut! Abitur-Prognose: ~1,5-2,0')
        elif overall >= 9:
            lines.append('→ Befriedigend. Abitur-Prognose: ~2,5-3,0')
        elif overall >= 5:
            lines.append('⚠ Ausreichend. Gezielt schwache Fächer verbessern!')
        else:
            lines.append('❗ Mangelhaft. Dringend handeln!')

        return '\n'.join(lines)
    except Exception:
        return 'Fehler bei der Notenanalyse.'


def _build_motivation(load_school_fn):
    """Give motivational response based on current data."""
    now = datetime.now()
    lines = []

    # Check achievements
    tasks = db.get_hub_tasks('completed')
    recent_completed = [t for t in tasks if t.get('completed_at', '')[:10] >= (now - timedelta(days=7)).strftime('%Y-%m-%d')]

    pomo = db.get_pomodoro_stats('week')
    pomo_hours = round((pomo.get('total_minutes', 0) or 0) / 60, 1)

    lines.append('**Du schaffst das!** 💪\n')

    if recent_completed:
        lines.append(f'Du hast diese Woche schon **{len(recent_completed)} Aufgaben** erledigt – das ist super!')

    if pomo_hours > 0:
        lines.append(f'**{pomo_hours} Stunden** gelernt diese Woche – jede Minute zählt!')

    import random
    tips = [
        '🎯 **Tipp:** Setz dir ein kleines Ziel für die nächsten 25 Minuten (Pomodoro).',
        '🧠 **Tipp:** Schwieriges zuerst – dein Gehirn ist am Anfang am leistungsfähigsten.',
        '💡 **Tipp:** Erkläre den Stoff jemand anderem – das festigt dein Wissen.',
        '📝 **Tipp:** Schreibe Zusammenfassungen per Hand – das verbessert die Erinnerung.',
        '🎵 **Tipp:** Instrumentalmusik kann beim Lernen helfen (keine Texte!).',
        '💧 **Tipp:** Trinke Wasser und mach alle 45 Min. eine kurze Pause.',
        '📱 **Tipp:** Handy in einen anderen Raum legen – aus den Augen, aus dem Sinn.',
        '🏃 **Tipp:** 10 Minuten Bewegung vor dem Lernen steigert die Konzentration.',
    ]
    lines.append(f'\n{random.choice(tips)}')

    # Check if there's something urgent
    if load_school_fn:
        try:
            _, _, exams, _, _ = load_school_fn()
            today = now.strftime('%Y-%m-%d')
            soon = [e for e in exams if today <= e.get('date', '') <= (now + timedelta(days=3)).strftime('%Y-%m-%d')]
            if soon:
                lines.append(f'\n⏰ Du hast in **{len(soon)} Tag(en) eine Klausur** – fang jetzt an, du wirst es nicht bereuen!')
        except Exception:
            pass

    lines.append('\n*"Der beste Zeitpunkt anzufangen war gestern. Der zweitbeste ist jetzt."*')
    return '\n'.join(lines)


def _build_deadline_countdown(load_school_fn, today):
    """Show countdown to all upcoming deadlines."""
    now = datetime.now()
    deadlines = []

    # Tasks with due dates
    tasks = db.get_hub_tasks('all')
    for t in tasks:
        if not t.get('completed') and t.get('due_date'):
            try:
                d = datetime.strptime(t['due_date'], '%Y-%m-%d').date()
                days = (d - now.date()).days
                if days >= 0:
                    deadlines.append(('📋', t['title'], days, t['due_date']))
            except ValueError:
                pass

    # School deadlines
    if load_school_fn:
        try:
            subjects, homework, exams, tests, _ = load_school_fn()
            subj_map = {s.get('id', ''): s.get('name', '') for s in subjects}

            for h in homework:
                if not h.get('completed') and h.get('due_date'):
                    try:
                        d = datetime.strptime(h['due_date'], '%Y-%m-%d').date()
                        days = (d - now.date()).days
                        if days >= 0:
                            subj = subj_map.get(h.get('subject_id', ''), '')
                            label = f'{h["title"]}{" [" + subj + "]" if subj else ""}'
                            deadlines.append(('📝', label, days, h['due_date']))
                    except ValueError:
                        pass

            for e in exams:
                if e.get('date', '') >= today:
                    try:
                        d = datetime.strptime(e['date'], '%Y-%m-%d').date()
                        days = (d - now.date()).days
                        subj = subj_map.get(e.get('subject_id', ''), '')
                        label = f'Klausur: {e.get("title", "")} [{subj}]'
                        deadlines.append(('🔴', label, days, e['date']))
                    except ValueError:
                        pass

            for t in tests:
                if t.get('date', '') >= today:
                    try:
                        d = datetime.strptime(t['date'], '%Y-%m-%d').date()
                        days = (d - now.date()).days
                        subj = subj_map.get(t.get('subject_id', ''), '')
                        label = f'Test: {t.get("title", "")} [{subj}]'
                        deadlines.append(('🟡', label, days, t['date']))
                    except ValueError:
                        pass
        except Exception:
            pass

    if not deadlines:
        return 'Keine anstehenden Deadlines – alles erledigt!'

    deadlines.sort(key=lambda x: x[2])
    lines = ['**Deadline-Countdown:**\n']
    for icon, label, days, date_str in deadlines[:15]:
        if days == 0:
            urgency = '**HEUTE!**'
        elif days == 1:
            urgency = '**morgen!**'
        elif days <= 3:
            urgency = f'**in {days} Tagen** ⚠'
        elif days <= 7:
            urgency = f'in {days} Tagen'
        else:
            urgency = f'in {days} Tagen ({_format_date_de(date_str)})'
        lines.append(f'  {icon} {label} – {urgency}')

    return '\n'.join(lines)


def _build_smart_tip(load_school_fn, today, weekday, now):
    """Generate a contextual smart tip based on current data."""
    tips = []

    # Time-based tips
    hour = now.hour
    if hour < 10:
        tips.append('☀ Guten Morgen! Vormittags lernt es sich am besten – nutze die frische Energie.')
    elif hour >= 22:
        tips.append('🌙 Es ist spät! Schlaf ist wichtiger als Lernen – morgen ist auch ein Tag.')

    # Check overdue tasks
    overdue = db.get_hub_tasks('overdue')
    if len(overdue) > 3:
        tips.append(f'📋 Du hast {len(overdue)} überfällige Aufgaben. Nimm dir 15 Minuten und arbeite die einfachsten ab.')
    elif overdue:
        tips.append(f'📋 {len(overdue)} überfällige Aufgabe(n) – erledige sie heute, dann hast du den Kopf frei.')

    # Check upcoming exams
    if load_school_fn:
        try:
            _, _, exams, tests, grades = load_school_fn()
            upcoming = [e for e in exams + tests if today <= e.get('date', '') <= (now + timedelta(days=7)).strftime('%Y-%m-%d')]
            if upcoming:
                tips.append(f'📚 {len(upcoming)} Prüfung(en) diese Woche! Starte jetzt mit einer Pomodoro-Session.')

            # Check weak subjects
            subj_avgs = {}
            for g in grades:
                sid = g.get('subject_id', '')
                v = g.get('points', g.get('grade_value', 0))
                subj_avgs.setdefault(sid, []).append(v)
            weak = [(sid, sum(vs)/len(vs)) for sid, vs in subj_avgs.items() if sum(vs)/len(vs) < 7]
            if weak:
                tips.append(f'⚠ {len(weak)} Fach/Fächer unter 7 Punkten – investiere dort extra Lernzeit.')
        except Exception:
            pass

    # Weekend tips
    if weekday >= 5:
        tips.append('🏖 Wochenende! Nutze die Zeit für Vorarbeit oder gönn dir eine Pause – beides ist OK.')

    # Pomodoro suggestion
    pomo = db.get_pomodoro_stats('week')
    if (pomo.get('total_sessions', 0) or 0) == 0:
        tips.append('🍅 Diese Woche noch keine Pomodoro-Session. Starte mit 25 Minuten fokussiertem Lernen!')

    if not tips:
        tips.append('✨ Alles unter Kontrolle! Mach weiter so.')

    lines = ['**Smart-Tipps für dich:**\n']
    lines.extend(f'  • {t}' for t in tips)
    return '\n'.join(lines)


def _build_productivity_stats():
    """Show productivity overview."""
    now = datetime.now()
    week_ago = (now - timedelta(days=7)).strftime('%Y-%m-%d')
    month_ago = (now - timedelta(days=30)).strftime('%Y-%m-%d')

    # Tasks
    all_tasks = db.get_hub_tasks('all')
    week_completed = len([t for t in all_tasks if t.get('completed') and t.get('completed_at', '')[:10] >= week_ago])
    month_completed = len([t for t in all_tasks if t.get('completed') and t.get('completed_at', '')[:10] >= month_ago])
    open_tasks = len([t for t in all_tasks if not t.get('completed')])
    overdue = len(db.get_hub_tasks('overdue'))

    # Pomodoro
    week_pomo = db.get_pomodoro_stats('week')
    month_pomo = db.get_pomodoro_stats('month')

    # Training
    sessions = db.get_hub_training_sessions(limit=100)
    week_training = len([s for s in sessions if s.get('date', '') >= week_ago])
    month_training = len([s for s in sessions if s.get('date', '') >= month_ago])

    lines = ['**Produktivitäts-Dashboard:**\n']
    lines.append('**Diese Woche:**')
    lines.append(f'  • {week_completed} Tasks erledigt')
    lines.append(f'  • {week_pomo.get("total_sessions", 0)} Pomodoro-Sessions ({round((week_pomo.get("total_minutes", 0) or 0)/60, 1)}h)')
    lines.append(f'  • {week_training} Trainingseinheiten')

    lines.append('\n**Dieser Monat:**')
    lines.append(f'  • {month_completed} Tasks erledigt')
    lines.append(f'  • {month_pomo.get("total_sessions", 0)} Pomodoro-Sessions ({round((month_pomo.get("total_minutes", 0) or 0)/60, 1)}h)')
    lines.append(f'  • {month_training} Trainingseinheiten')

    lines.append('\n**Aktuell:**')
    lines.append(f'  • {open_tasks} offene Aufgaben')
    if overdue:
        lines.append(f'  • ⚠ {overdue} überfällig')

    # Completion rate
    total = week_completed + open_tasks
    if total > 0:
        rate = round(week_completed / total * 100)
        bar_filled = rate // 10
        bar = '█' * bar_filled + '░' * (10 - bar_filled)
        lines.append(f'\n**Abschlussrate:** [{bar}] {rate}%')

    return '\n'.join(lines)


def _build_day_summary(today, weekday, now, load_school_fn=None):
    lines = [f'**{DAY_NAMES_DE[weekday]}, {now.strftime("%d.%m.%Y")}**\n']

    # Timetable (only on weekdays)
    db_day = _weekday_to_db_day(weekday)
    if db_day is None:
        lines.append('**Wochenende** – kein Unterricht.\n')
    else:
        try:
            entries = db.get_timetable_entries(day=db_day)
            settings = db.get_timetable_settings()
            has_ab = settings.get('has_ab_weeks', True) if settings else True
            ref_date = settings.get('reference_date') if settings else None
            week_type = 'both'
            if has_ab and ref_date:
                try:
                    ref = datetime.strptime(ref_date, '%Y-%m-%d')
                    diff_weeks = abs((now - ref).days) // 7
                    week_type = 'A' if diff_weeks % 2 == 0 else 'B'
                except Exception:
                    pass
            if week_type != 'both':
                entries = [e for e in entries if e.get('week', 'both') in ('both', week_type)]
            periods = db.get_timetable_periods()
            period_map = {p['period_number']: p for p in periods}

            if entries:
                entries.sort(key=lambda e: e.get('block', 0))
                lines.append('**Unterricht:**')
                for e in entries:
                    block = e.get('block', 0)
                    p = period_map.get(block, {})
                    time_str = p.get('start_time') or f'Block {block}'
                    room = f' (R. {e["room"]})' if e.get('room') else ''
                    lines.append(f'  • {time_str}: {e.get("subject", "?")}{room}')
                lines.append('')
            else:
                lines.append('Kein Unterricht heute.\n')
        except Exception:
            pass

    # Tasks
    tasks = db.get_hub_tasks('today')
    open_tasks = [t for t in tasks if not t.get('completed')]
    if open_tasks:
        lines.append(f'**Aufgaben ({len(open_tasks)}):**')
        for t in open_tasks[:8]:
            prio_mark = ' ❗' if t.get('priority') == 'high' else ''
            time_str = f' um {t["due_time"]}' if t.get('due_time') else ''
            lines.append(f'  • {t["title"]}{time_str}{prio_mark}')
        lines.append('')
    else:
        lines.append('**Aufgaben:** Keine für heute.\n')

    # Homework
    if load_school_fn:
        try:
            subjects, homework, exams, tests, _ = load_school_fn()
            subj_map = {s.get('id', ''): s.get('name', '') for s in subjects}
            open_hw = [h for h in homework if not h.get('completed') and h.get('due_date', '') <= today]
            if open_hw:
                lines.append(f'**Hausaufgaben fällig ({len(open_hw)}):**')
                for h in open_hw[:5]:
                    subj = subj_map.get(h.get('subject_id', ''), '')
                    lines.append(f'  • {h["title"]}{" [" + subj + "]" if subj else ""}')
                lines.append('')

            upcoming_exams = [e for e in exams if e.get('date', '') >= today]
            upcoming_exams.sort(key=lambda e: e.get('date', ''))
            if upcoming_exams:
                next_exam = upcoming_exams[0]
                subj = subj_map.get(next_exam.get('subject_id', ''), '')
                lines.append(f'**Nächste Klausur:** {next_exam.get("title", "Klausur")} [{subj}] am {_format_date_de(next_exam["date"])}')
                lines.append('')
        except Exception:
            pass

    # Overdue
    overdue = db.get_hub_tasks('overdue')
    if overdue:
        lines.append(f'⚠ {len(overdue)} überfällige Aufgabe{"n" if len(overdue) != 1 else ""}!')

    return '\n'.join(lines)


def _build_week_summary(today, now, load_school_fn=None):
    end_of_week = (now + timedelta(days=(6 - now.weekday()))).strftime('%Y-%m-%d')
    lines = [f'**Wochenübersicht ({now.strftime("%d.%m.")} – {(now + timedelta(days=6-now.weekday())).strftime("%d.%m.")})**\n']

    # Tasks this week
    all_tasks = db.get_hub_tasks('all')
    week_tasks = [t for t in all_tasks if not t.get('completed') and (t.get('due_date') or '') and today <= (t.get('due_date') or '') <= end_of_week]
    completed = [t for t in all_tasks if t.get('completed') and (t.get('completed_at') or '')[:10] >= today]

    lines.append(f'**Tasks:** {len(week_tasks)} offen, {len(completed)} erledigt')

    if week_tasks:
        for t in sorted(week_tasks, key=lambda x: x.get('due_date') or '')[:8]:
            day = _format_date_de(t['due_date']) if t.get('due_date') else ''
            lines.append(f'  • {t["title"]} ({day})')
    lines.append('')

    # School
    if load_school_fn:
        try:
            subjects, homework, exams, tests, grades = load_school_fn()
            subj_map = {s.get('id', ''): s.get('name', '') for s in subjects}

            week_hw = [h for h in homework if not h.get('completed') and today <= h.get('due_date', '') <= end_of_week]
            if week_hw:
                lines.append(f'**Hausaufgaben ({len(week_hw)}):**')
                for h in week_hw[:6]:
                    subj = subj_map.get(h.get('subject_id', ''), '')
                    lines.append(f'  • {h["title"]}{" [" + subj + "]" if subj else ""} ({_format_date_de(h.get("due_date", ""))})')
                lines.append('')

            week_exams = [e for e in exams if today <= e.get('date', '') <= end_of_week]
            week_tests = [t for t in tests if today <= t.get('date', '') <= end_of_week]
            if week_exams or week_tests:
                lines.append('**Prüfungen diese Woche:**')
                for e in week_exams:
                    subj = subj_map.get(e.get('subject_id', ''), '')
                    lines.append(f'  • 📝 Klausur: {e.get("title", "")} [{subj}] am {_format_date_de(e["date"])}')
                for t in week_tests:
                    subj = subj_map.get(t.get('subject_id', ''), '')
                    lines.append(f'  • Test: {t.get("title", "")} [{subj}] am {_format_date_de(t["date"])}')
                lines.append('')
        except Exception:
            pass

    # Pomodoro
    pomo = db.get_pomodoro_stats('week')
    if pomo.get('total_sessions', 0) > 0:
        hours = round((pomo.get('total_minutes', 0) or 0) / 60, 1)
        lines.append(f'**Pomodoro:** {pomo["total_sessions"]} Sessions ({hours}h)')

    # Training
    sessions = db.get_hub_training_sessions(limit=20)
    week_sessions = [s for s in sessions if s.get('date', '') >= today]
    if week_sessions:
        lines.append(f'**Training:** {len(week_sessions)} Einheiten diese Woche')

    return '\n'.join(lines)


def _build_timetable_response(weekday, now, msg):
    # Check if asking about a specific day
    target_day = weekday
    for i, name in enumerate(DAY_NAMES_DE):
        if name.lower() in msg:
            target_day = i
            break
    if 'morgen' in msg:
        target_day = (weekday + 1) % 7

    db_day = _weekday_to_db_day(target_day)
    if db_day is None:
        return f'Am {DAY_NAMES_DE[target_day]} ist kein Unterricht (Wochenende).'

    entries = db.get_timetable_entries(day=db_day)
    settings = db.get_timetable_settings()
    has_ab = settings.get('has_ab_weeks', True) if settings else True
    ref_date = settings.get('reference_date') if settings else None

    week_type = 'both'
    if has_ab and ref_date:
        try:
            ref = datetime.strptime(ref_date, '%Y-%m-%d')
            days_diff = abs((now - ref).days)
            if target_day != weekday:
                days_diff += (target_day - weekday)
            diff_weeks = days_diff // 7
            week_type = 'A' if diff_weeks % 2 == 0 else 'B'
        except Exception:
            pass

    if week_type != 'both':
        entries = [e for e in entries if e.get('week', 'both') in ('both', week_type)]

    if not entries:
        return f'Kein Unterricht am {DAY_NAMES_DE[target_day]}.'

    periods = db.get_timetable_periods()
    period_map = {p['period_number']: p for p in periods}
    entries.sort(key=lambda e: e.get('block', 0))

    week_label = f' (Woche {week_type})' if week_type != 'both' else ''
    lines = [f'**Stundenplan {DAY_NAMES_DE[target_day]}{week_label}:**\n']
    for e in entries:
        block = e.get('block', 0)
        p = period_map.get(block, {})
        time_range = f'{p.get("start_time", "?")} – {p.get("end_time", "?")}' if p.get('start_time') else f'Block {block}'
        room = f', Raum {e["room"]}' if e.get('room') else ''
        teacher = f' ({e["teacher"]})' if e.get('teacher') else ''
        stype = f' {e["subject_type"]}' if e.get('subject_type') else ''
        lines.append(f'  • {time_range}: **{e.get("subject", "?")}{stype}**{room}{teacher}')

    return '\n'.join(lines)


def _build_tasks_response():
    all_tasks = db.get_hub_tasks('all')
    open_tasks = [t for t in all_tasks if not t.get('completed')]
    if not open_tasks:
        return 'Alle Aufgaben erledigt – gut gemacht! 🎉'

    # Group by priority
    high = [t for t in open_tasks if t.get('priority') == 'high']
    medium = [t for t in open_tasks if t.get('priority') == 'medium']
    low = [t for t in open_tasks if t.get('priority') == 'low']
    other = [t for t in open_tasks if t.get('priority') not in ('high', 'medium', 'low')]

    lines = [f'**Offene Aufgaben ({len(open_tasks)}):**\n']
    for label, group in [('🔴 Hoch', high), ('🟡 Mittel', medium), ('🟢 Niedrig', low), ('Sonstige', other)]:
        if group:
            lines.append(f'**{label}:**')
            for t in sorted(group, key=lambda x: x.get('due_date') or '9999')[:6]:
                due = f' – {_format_date_de(t["due_date"])}' if t.get('due_date') else ''
                lines.append(f'  • {t["title"]}{due}')
    return '\n'.join(lines)


def _build_homework_response(load_school_fn, today):
    if not load_school_fn:
        return 'Keine Schuldaten verfügbar.'
    try:
        subjects, homework, _, _, _ = load_school_fn()
        subj_map = {s.get('id', ''): s.get('name', '') for s in subjects}
        open_hw = [h for h in homework if not h.get('completed')]
        if not open_hw:
            return 'Keine offenen Hausaufgaben!'
        open_hw.sort(key=lambda h: h.get('due_date', '9999'))
        lines = [f'**Offene Hausaufgaben ({len(open_hw)}):**\n']
        for h in open_hw[:12]:
            subj = subj_map.get(h.get('subject_id', ''), '')
            due = _format_date_de(h['due_date']) if h.get('due_date') else 'kein Datum'
            overdue = ' ⚠️' if h.get('due_date', '9999') < today else ''
            lines.append(f'  • {h["title"]}{" [" + subj + "]" if subj else ""} – {due}{overdue}')
        return '\n'.join(lines)
    except Exception:
        return 'Fehler beim Laden der Hausaufgaben.'


def _build_exams_response(load_school_fn, today):
    if not load_school_fn:
        return 'Keine Schuldaten verfügbar.'
    try:
        subjects, _, exams, tests, _ = load_school_fn()
        subj_map = {s.get('id', ''): s.get('name', '') for s in subjects}
        upcoming_exams = sorted([e for e in exams if e.get('date', '') >= today], key=lambda e: e['date'])
        upcoming_tests = sorted([t for t in tests if t.get('date', '') >= today], key=lambda t: t['date'])

        if not upcoming_exams and not upcoming_tests:
            return 'Keine anstehenden Klausuren oder Tests.'

        lines = ['**Anstehende Prüfungen:**\n']
        if upcoming_exams:
            lines.append('**Klausuren:**')
            for e in upcoming_exams[:8]:
                subj = subj_map.get(e.get('subject_id', ''), '')
                days_until = (datetime.strptime(e['date'], '%Y-%m-%d').date() - datetime.now().date()).days
                urgency = ' ❗' if days_until <= 3 else ''
                topics = f'\n    Themen: {e["topics"]}' if e.get('topics') else ''
                lines.append(f'  • {e.get("title", "Klausur")} [{subj}] – {_format_date_de(e["date"])}{_days_suffix(days_until)}{urgency}{topics}')
            lines.append('')

        if upcoming_tests:
            lines.append('**Tests:**')
            for t in upcoming_tests[:8]:
                subj = subj_map.get(t.get('subject_id', ''), '')
                lines.append(f'  • {t.get("title", "Test")} [{subj}] – {_format_date_de(t["date"])}')

        return '\n'.join(lines)
    except Exception:
        return 'Fehler beim Laden der Prüfungen.'


def _build_grades_response(load_school_fn):
    if not load_school_fn:
        return 'Keine Schuldaten verfügbar.'
    try:
        subjects, _, _, _, grades = load_school_fn()
        if not grades:
            return 'Noch keine Noten eingetragen.'
        subj_map = {s.get('id', ''): s.get('name', '') for s in subjects}

        # Group by subject
        by_subj = {}
        for g in grades:
            sid = g.get('subject_id', '')
            if sid not in by_subj:
                by_subj[sid] = []
            by_subj[sid].append(g.get('points', g.get('grade_value', 0)))

        lines = [f'**Notenübersicht ({len(grades)} Noten):**\n']
        overall_sum, overall_count = 0, 0
        for sid, values in sorted(by_subj.items(), key=lambda x: subj_map.get(x[0], x[0])):
            name = subj_map.get(sid, sid)
            avg = sum(values) / len(values)
            trend = ''
            if len(values) >= 3:
                recent = sum(values[-2:]) / 2
                older = sum(values[:-2]) / max(len(values) - 2, 1)
                if recent > older + 0.5:
                    trend = ' ↑'
                elif recent < older - 0.5:
                    trend = ' ↓'
            lines.append(f'  • **{name}**: Ø {avg:.1f} ({len(values)} Noten){trend}')
            overall_sum += sum(values)
            overall_count += len(values)

        if overall_count > 0:
            lines.append(f'\n**Gesamtdurchschnitt: {overall_sum / overall_count:.1f}**')

        return '\n'.join(lines)
    except Exception:
        return 'Fehler beim Laden der Noten.'


def _build_study_plan(load_school_fn, today, msg):
    if not load_school_fn:
        return 'Keine Schuldaten verfügbar für einen Lernplan.'
    try:
        subjects, _, exams, tests, grades = load_school_fn()
        subj_map = {s.get('id', ''): s.get('name', '') for s in subjects}

        # Find which subject user is asking about
        target_subject = None
        for s in subjects:
            if s.get('name', '').lower() in msg:
                target_subject = s
                break

        # Find upcoming exams
        upcoming = sorted(
            [e for e in exams + tests if e.get('date', '') >= today],
            key=lambda e: e.get('date', '')
        )

        if target_subject:
            sid = target_subject.get('id', '')
            subj_exams = [e for e in upcoming if e.get('subject_id', '') == sid]
            subj_grades = [g.get('points', g.get('grade_value', 0)) for g in grades if g.get('subject_id', '') == sid]
            avg = sum(subj_grades) / len(subj_grades) if subj_grades else None

            lines = [f'**Lernplan: {target_subject["name"]}**\n']
            if avg is not None:
                lines.append(f'Aktueller Schnitt: **{avg:.1f}** Punkte')
                if avg < 5:
                    lines.append('→ Dringender Handlungsbedarf!\n')
                elif avg < 9:
                    lines.append('→ Ausbaufähig – regelmäßig lernen.\n')
                else:
                    lines.append('→ Gutes Niveau – weiter so!\n')

            if subj_exams:
                next_exam = subj_exams[0]
                days_until = (datetime.strptime(next_exam['date'], '%Y-%m-%d').date() - datetime.now().date()).days
                lines.append(f'Nächste Prüfung: **{next_exam.get("title", "Klausur")}** {_in_days(days_until)}')
                topics = next_exam.get('topics', '')
                if topics:
                    lines.append(f'Themen: {topics}\n')

                lines.append('**Empfohlener Plan:**')
                if days_until <= 1:
                    lines.append('  • Zusammenfassungen durchgehen')
                    lines.append('  • Karteikarten wiederholen')
                    lines.append('  • Früh schlafen gehen!')
                elif days_until <= 3:
                    lines.append('  • Tag 1: Übungsaufgaben lösen')
                    lines.append('  • Tag 2: Schwache Themen nacharbeiten')
                    lines.append('  • Tag 3: Probeklausur + Zusammenfassung')
                elif days_until <= 7:
                    lines.append('  • Tag 1-2: Stoff durchlesen & strukturieren')
                    lines.append('  • Tag 3-4: Übungsaufgaben & Altklausuren')
                    lines.append('  • Tag 5: Schwache Stellen gezielt wiederholen')
                    lines.append('  • Tag 6: Probeklausur simulieren')
                    lines.append('  • Tag 7: Leichte Wiederholung & Erholung')
                else:
                    weeks = days_until // 7
                    lines.append('  • Woche 1: Stoff lesen und Zusammenfassungen erstellen')
                    lines.append('  • Woche 2: Übungsaufgaben und aktives Lernen')
                    if weeks >= 3:
                        lines.append('  • Woche 3+: Altklausuren, Lerngruppen, Schwächen ausmerzen')
                    lines.append('  • Letzte Woche: Probeklausuren und Wiederholung')
            else:
                lines.append('Keine anstehende Prüfung in diesem Fach.')

            lines.append('\n💡 Tipp: Nutze Pomodoro-Sessions (25 Min. fokussiert lernen, 5 Min. Pause).')
            return '\n'.join(lines)

        # No specific subject → general study overview
        if not upcoming:
            return 'Keine anstehenden Prüfungen. Nutze die Zeit zum Vorlernen oder Wiederholen!'

        lines = ['**Lernempfehlung:**\n']
        lines.append('Nächste Prüfungen:')
        for e in upcoming[:5]:
            subj = subj_map.get(e.get('subject_id', ''), '')
            days_until = (datetime.strptime(e['date'], '%Y-%m-%d').date() - datetime.now().date()).days
            urgency = ' ❗ DRINGEND' if days_until <= 3 else ''
            lines.append(f'  • {e.get("title", "Prüfung")} [{subj}] {_in_days(days_until)}{urgency}')

        lines.append('\n💡 Frag mich nach einem Fach für einen detaillierten Lernplan (z.B. "Lernplan für Mathe").')
        return '\n'.join(lines)
    except Exception:
        return 'Fehler beim Erstellen des Lernplans.'


def _build_training_response():
    sessions = db.get_hub_training_sessions(limit=10)
    if not sessions:
        return 'Noch keine Trainingseinheiten aufgezeichnet.'

    goals = db.get_hub_training_goals(completed=False)
    health = db.get_hub_training_health(limit=7)

    lines = ['**Training-Übersicht:**\n']
    lines.append('**Letzte Einheiten:**')
    for s in sessions[:5]:
        dur = f' ({s["duration"]} Min.)' if s.get('duration') else ''
        cal = f', {s["calories"]} kcal' if s.get('calories') else ''
        lines.append(f'  • {s.get("type", "Training")} am {_format_date_de(s.get("date", ""))}{dur}{cal}')

    if goals:
        lines.append(f'\n**Offene Ziele ({len(goals)}):**')
        for g in goals[:5]:
            progress = f' ({g.get("current", 0)}/{g.get("target", "?")}{" " + g.get("unit", "") if g.get("unit") else ""})' if g.get('target') else ''
            lines.append(f'  • {g["title"]}{progress}')

    if health:
        latest = health[0]
        parts = []
        if latest.get('sleep'):
            parts.append(f'Schlaf: {latest["sleep"]}h')
        if latest.get('energy'):
            parts.append(f'Energie: {latest["energy"]}/10')
        if parts:
            lines.append(f'\n**Gesundheit ({_format_date_de(latest.get("date", ""))}):** {", ".join(parts)}')

    return '\n'.join(lines)


def _build_pomodoro_response():
    week_stats = db.get_pomodoro_stats('week')
    month_stats = db.get_pomodoro_stats('month')

    week_h = round((week_stats.get('total_minutes', 0) or 0) / 60, 1)
    month_h = round((month_stats.get('total_minutes', 0) or 0) / 60, 1)

    lines = ['**Pomodoro-Statistiken:**\n']
    lines.append(f'**Diese Woche:** {week_stats.get("total_sessions", 0)} Sessions ({week_h}h)')
    lines.append(f'**Dieser Monat:** {month_stats.get("total_sessions", 0)} Sessions ({month_h}h)')

    if month_stats.get('by_subject'):
        lines.append('\n**Nach Fach (30 Tage):**')
        for s in month_stats['by_subject'][:6]:
            h = round((s.get('minutes', 0) or 0) / 60, 1)
            lines.append(f'  • Fach #{s.get("subject_id", "?")}: {h}h ({s.get("sessions", 0)} Sessions)')

    return '\n'.join(lines)


def _build_review_response():
    reviews = db.get_hub_reviews(limit=5)
    if not reviews:
        return 'Noch keine Reviews geschrieben. Starte doch mit einer täglichen Reflexion!'

    lines = ['**Letzte Reviews:**\n']
    for r in reviews:
        date = _format_date_de(r.get('date', ''))
        rtype = 'Tagesreview' if r.get('type') == 'daily' else 'Wochenreview'
        energy = f' (Energie: {r["energy"]}/10)' if r.get('energy') else ''

        data = r.get('data')
        preview = ''
        if data:
            try:
                d = json.loads(data) if isinstance(data, str) else data
                if isinstance(d, dict):
                    for key in ['highlight', 'summary', 'gratitude', 'accomplished']:
                        if d.get(key):
                            preview = f'\n    → {str(d[key])[:100]}'
                            break
            except Exception:
                pass

        lines.append(f'  • **{rtype}** ({date}){energy}{preview}')

    return '\n'.join(lines)
