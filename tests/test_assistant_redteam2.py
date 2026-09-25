# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

"""Round-2 red team — adversarial phrasings + Unicode/encoding attacks."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('SECRET_KEY', 'redteam-secret')

from app.assistant_service import offline_response
import re

CASES = [
    # ─── Negation — must NOT reply as if the negated thing was requested ───
    ('neg',  'Ich habe KEINE Lust auf Mitternachtsformel',               'NOT_formula'),
    ('neg',  'Nicht die pq-Formel bitte',                                'NOT_formula'),
    ('neg',  'Kein Pythagoras',                                          'NOT_formula'),
    ('neg',  'Ich mag die Romantik nicht',                               'NOT_epoch'),

    # ─── Partial / truncated names ───
    ('part', 'Sturm',                                                     'NOT_epoch'),
    ('part', 'Drang',                                                     'NOT_epoch'),
    ('part', 'Klassik',                                                   'epoch'),          # actually a valid alias
    ('part', 'Mittern',                                                   'NOT_math'),
    ('part', 'Pyth',                                                      'NOT_math'),

    # ─── Quotes around entity names ───
    ('quo',  'Wer schrieb "Faust"?',                                      'werk'),
    ('quo',  "Wer schrieb 'Die Räuber'?",                                 'werk'),
    ('quo',  'Autor von «Der Prozess»',                                    'werk'),
    ('quo',  'Merkmale der „Romantik"',                                   'epoch'),

    # ─── Unicode homoglyphs / zero-width / BOM ───
    ('uni',  '\ufeffMitternachtsformel',                                  'formula'),  # BOM prefix
    ('uni',  'Mitternachts\u200bformel',                                  'NOT_math'), # ZWSP breaks token — ideally still finds it, at worst honest_unknown
    ('uni',  'Μitternachtsformel',                                         'NOT_math'),  # Greek Mu — homoglyph, expected to fail honestly
    ('uni',  '  \t  Pythagoras  \t  ',                                    'formula'),
    ('uni',  '\xa0Hallo\xa0',                                              'greeting'),  # non-breaking spaces

    # ─── HTML / markdown injection ───
    ('html', '<b>Mitternachtsformel</b>',                                  'formula'),
    ('html', '**Mitternachtsformel**',                                     'formula'),
    ('html', '<script>alert(1)</script>Mitternachtsformel',                ('formula', 'honest_unknown')),
    ('html', '[Mitternachtsformel](https://evil.com)',                     ('formula', 'honest_unknown')),

    # ─── Multi-line / copy-paste mess ───
    ('ml',   'Was ist die\n\nMitternachtsformel?',                         'formula'),
    ('ml',   'Hallo\nWer schrieb Faust?\nDanke',                           ('werk', 'greeting')),
    ('ml',   '\n\n\n\n',                                                    'honest_unknown'),

    # ─── Sentence fragments ───
    ('frag', 'Die Mitternachtsformel lautet',                              'formula'),
    ('frag', 'Faust wurde geschrieben von',                                ('werk', 'honest_unknown')),
    ('frag', 'Merkmale',                                                    'honest_unknown'),

    # ─── Abbreviations ───
    ('abbr', 'pq-F.',                                                      ('formula', 'honest_unknown')),
    ('abbr', 'Mitternachtsf.',                                             ('formula', 'honest_unknown')),

    # ─── Math edge cases ───
    ('mE',   '1 durch 0',                                                   'math'),  # div by zero handled
    ('mE',   'wurzel aus 0',                                                'math'),
    ('mE',   'wurzel aus -1',                                                'honest_unknown'),  # invalid
    ('mE',   '0 mal 9999',                                                   'math'),
    ('mE',   '2 hoch 50',                                                    'math'),
    ('mE',   '(5+3)*(2-1)',                                                  'math'),
    ('mE',   '-5 + -3',                                                      'math'),

    # ─── Date edge cases ───
    ('dE',   'welcher tag ist der 29.02.2025',                               'honest_unknown'),  # 2025 not a leap year
    ('dE',   'welcher tag ist der 29.02.2024',                               'date'),            # leap year — ok
    ('dE',   'welcher tag ist der 32.13.2026',                               'honest_unknown'),  # invalid day/month
    ('dE',   'Wie spät',                                                     'date'),            # short
    ('dE',   'wie spät ists',                                                ('date', 'honest_unknown')),  # missing "es"

    # ─── Too-specific queries ───
    ('spec', 'Merkmale des späten Expressionismus',                         'epoch'),
    ('spec', 'Autoren des frühen Realismus',                                'epoch'),

    # ─── Leading/trailing noise ───
    ('noise','bla bla wer schrieb Faust?',                                  'werk'),
    ('noise','Wer schrieb Faust, ich weiß es wirklich nicht mehr.',         'werk'),
    ('noise','Hmmm, also, die Mitternachtsformel?',                          'formula'),
    ('noise','Kurze Frage: Merkmale der Romantik',                          'epoch'),

    # ─── Compound "und" queries ───
    ('und',  'Mitternachtsformel und Pythagoras',                           'formula'),
    ('und',  'Goethe und Schiller',                                         'NOT_math'),   # no intent phrase — chitchat

    # ─── Misleading / confusing ───
    ('conf', 'Welche Klasse war Einstein in?',                              ('wikipedia', 'honest_unknown')),  # not a topics lookup
    ('conf', 'Klasse 12 ist so stressig',                                   'NOT_topics'),
    ('conf', 'Ich mag Physik Grundkurs aber Chemie nicht',                  'NOT_topics'),
    ('conf', 'In der 7. Klasse hatten wir Englisch',                        'NOT_topics'),     # past tense, no intent

    # ─── Repeated words ───
    ('rep',  'Faust Faust Faust',                                           'NOT_math'),
    ('rep',  'pq pq pq',                                                    'NOT_math'),
    ('rep',  'Ableitung Ableitung',                                         ('formula', 'honest_unknown')),

    # ─── Only punctuation/emoji ───
    ('junk', '???',                                                         'honest_unknown'),
    ('junk', '…',                                                            'honest_unknown'),
    ('junk', '🧮📐',                                                           'honest_unknown'),
    ('junk', '.',                                                             'honest_unknown'),

    # ─── Dialect / Jugendsprache ───
    ('slang','ey alter was is ne mitternachtsformel',                       'formula'),
    ('slang','yo kannste mir pythagoras erklären?',                         'formula'),
    ('slang','Bro ich brauch die Formel für den Kreis',                     'formula'),

    # ─── Long copy-paste ───
    ('big',  'Ich hatte heute in der Schule eine Aufgabe zur Mitternachtsformel. Kannst du mir die nochmal erklären?', 'formula'),
    ('big',  'A' * 5000,                                                    'honest_unknown'),  # huge garbage
    ('big',  ('Mitternachtsformel ' * 100).strip(),                          'formula'),

    # ─── Asking by result ───
    ('res',  'Mit welcher Formel berechnet man die Kreisfläche?',            'formula'),
    ('res',  'Wie berechnet man das Volumen einer Kugel?',                   'formula'),

    # ─── "Integral" (aliased to stammfunktion) ───
    ('int',  'Integral von x^2',                                             'formula'),
    ('int',  'Stammfunktion von sin',                                        ('formula', 'honest_unknown')),

    # ─── Dates in weird formats ───
    ('dtF',  'welcher tag ist der 2026-12-31',                               ('date', 'honest_unknown')),  # ISO format — nice-to-have
    ('dtF',  'Welcher Tag ist am 23/04/2026',                                ('date', 'honest_unknown')),

    # ─── Number-word math ───
    ('nw',   'zwei plus drei',                                               ('math', 'honest_unknown')),
    ('nw',   'zehn mal zehn',                                                ('math', 'honest_unknown')),
    ('nw',   'hundert durch vier',                                           ('math', 'honest_unknown')),

    # ─── Compound units ───
    ('cu',   '5 meter in fuß',                                               'unit'),
    ('cu',   '3 pound in kg',                                                'unit'),           # english spelling
    ('cu',   '100 miles in km',                                              'unit'),           # english plural

    # ─── Extra-spaced text ───
    ('sp',   'M i t t e r n a c h t s f o r m e l',                          ('formula', 'honest_unknown')),
    ('sp',   'P y t h a g o r a s',                                          ('formula', 'honest_unknown')),

    # ─── Tasks/todo phrasings ───
    ('t',    'Was hab ich noch zu tun?',                                     ('honest_unknown', 'other')),
    ('t',    'zeig mir meine tasks',                                         'other'),          # should list tasks
    ('t',    'liste todos',                                                  'other'),

    # ─── Time-sensitive ───
    ('time', 'Wie viele Stunden hat der Tag?',                               ('math', 'honest_unknown')),  # general knowledge
    ('time', 'Wie viele Minuten sind eine Stunde?',                          ('math', 'honest_unknown')),
]


def classify(response: str) -> str:
    r = response or ''
    if not r.strip():
        return 'empty'
    if re.search(r'\d\s*°[CFK]\s*=', r) or 'Meilen**' in r or 'Pfund**' in r or 'Gallonen**' in r or re.search(r'\*\*[\d.,]+\s+(?:km|m|ft|Fuß|kg|lb|l|Gallonen|Meilen|Pfund|Meter)\*\*', r):
        return 'unit'
    if re.search(r'\bKlasse \d+\b', r) and ('—' in r or 'typische Themen' in r):
        return 'topics'
    if '$$' in r and ('\\frac' in r or '\\pi' in r or '\\cdot' in r or '\\sqrt' in r or 'Beispiel' in r or '= ' in r):
        return 'formula'
    if ('Merkmale' in r and 'Autoren' in r) or ('Bekannte Werke' in r):
        return 'epoch'
    if re.search(r'\*\*[^*]+\*\*\s*—\s*\S', r) and re.search(r'(1[5-9]\d{2}|2\d{3})', r):
        return 'werk'
    if 'durch 0' in r or '% von' in r or '√' in r:
        return 'math'
    if re.fullmatch(r'\s*[^\n]{0,40}=\s*\*\*-?[\d.,]+\*\*\s*', r):
        return 'math'
    if re.search(r'(?:^|\n)[\d\s+\-*/().,·−÷^·]+\s*=\s*\*\*-?[\d.,]+\*\*\s*$', r.strip()):
        return 'math'
    if 'Heute ist' in r or 'Morgen ist' in r or re.search(r'Es ist \*\*\d{1,2}:\d{2}\*\*', r) or re.search(r'ist ein \*\*\w+tag\*\*', r):
        return 'date'
    if r.startswith('Guten Morgen') or r.startswith('Guten Tag') or r.startswith('Guten Abend'):
        return 'greeting'
    if 'konnte deine Frage' in r or 'keinen Wikipedia' in r or 'nicht zuverlässig bekannt' in r or 'Prüfe bitte die Schreibweise' in r or 'nicht wie eine natürliche Frage' in r:
        return 'honest_unknown'
    if 'Quelle: https://' in r or 'wikipedia.org' in r:
        return 'wikipedia'
    if 'Offene Aufgaben' in r or 'alle erledigt' in r.lower() or 'Alle Aufgaben erledigt' in r:
        return 'other'
    if 'Zusammenfassung' in r or 'Texthilfe' in r or 'Erörterung' in r:
        return 'text_help'
    return 'other'


def matches(got, exp):
    if isinstance(exp, tuple):
        return got in exp
    if isinstance(exp, str) and exp.startswith('NOT_'):
        return got != exp[4:]
    return got == exp



import pytest


@pytest.mark.parametrize('category,query,expected', CASES)
def test_redteam2_case(category, query, expected):
    from app.assistant_service import offline_response
    try:
        r = offline_response(query)
    except Exception as e:
        pytest.fail(f'[{category}] {query!r} raised {type(e).__name__}: {e}')
    got = classify(r)
    if not matches(got, expected):
        pytest.fail(f'[{category}] {query[:80]!r}\n  got={got!r}  exp={expected!r}\n  out: {r[:160]!r}')
