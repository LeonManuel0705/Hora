# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import re
import logging
import requests
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from .crypto_utils import encrypt_file, decrypt_file
from .paths import DATA_DIR

DB_API_BASE = "https://v6.db.transport.rest"
VBB_API_BASE = "https://v6.vbb.transport.rest"
DB_INTERNAL_API = "https://int.bahn.de/web/api"

TRANSPORT_APIS = [DB_API_BASE, VBB_API_BASE]

LOCATIONS_CACHE_FILE = DATA_DIR / 'vbb_locations_cache.json'

KNOWN_LOCATIONS_FILE = DATA_DIR / 'known_locations.json'

TICKET_CATALOG = [
    {'id': 'deutschlandticket', 'name': 'Deutschlandticket', 'category': 'national',
     'price': 63.0, 'period': 'month', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Alle Busse, Bahnen, S/U-Bahn, Regionalzüge deutschlandweit',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['49 euro', 'd-ticket', 'deutschland', 'nahverkehr', 'regional']},
    {'id': 'deutschlandticket_job', 'name': 'Deutschlandticket Job', 'category': 'national',
     'price': 40.60, 'period': 'month', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Arbeitgeber-bezuschusstes Deutschlandticket (max. 40,60 €/Monat)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['job', 'arbeitgeber', 'firmenticket', 'jobticket', 'deutschland']},
    {'id': 'bahncard25_2', 'name': 'BahnCard 25 (2. Klasse)', 'category': 'national',
     'price': 62.0, 'period': 'year', 'zone_coverage': 'none', 'covers_ice': True,
     'description': '25% Rabatt auf Flexpreise bei DB Fernverkehr',
     'min_age': None, 'max_age': None, 'is_discount_card': True, 'discount_percent': 25,
     'search_tags': ['bahncard', 'rabatt', 'fernverkehr', 'ice', 'ic']},
    {'id': 'bahncard25_2_jugend', 'name': 'My BahnCard 25 (Jugend, 2. Kl.)', 'category': 'national',
     'price': 10.0, 'period': 'year', 'zone_coverage': 'none', 'covers_ice': True,
     'description': '25% Rabatt auf Flexpreise, für Reisende unter 27 Jahren',
     'min_age': None, 'max_age': 26, 'is_discount_card': True, 'discount_percent': 25,
     'search_tags': ['bahncard', 'jugend', 'jung', 'rabatt', 'my bahncard']},
    {'id': 'bahncard50_2', 'name': 'BahnCard 50 (2. Klasse)', 'category': 'national',
     'price': 255.0, 'period': 'year', 'zone_coverage': 'none', 'covers_ice': True,
     'description': '50% Rabatt auf Flexpreise bei DB Fernverkehr',
     'min_age': None, 'max_age': None, 'is_discount_card': True, 'discount_percent': 50,
     'search_tags': ['bahncard', 'rabatt', 'fernverkehr', 'ice', 'ic', 'halber preis']},
    {'id': 'bahncard100_2', 'name': 'BahnCard 100 (2. Klasse)', 'category': 'national',
     'price': 4899.0, 'period': 'year', 'zone_coverage': 'all', 'covers_ice': True,
     'description': 'Freie Fahrt in allen Zügen inkl. ICE/IC + Nahverkehr deutschlandweit',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['bahncard', 'flatrate', 'alles', 'unbegrenzt']},
    {'id': 'bahncard25_1', 'name': 'BahnCard 25 (1. Klasse)', 'category': 'national',
     'price': 125.0, 'period': 'year', 'zone_coverage': 'none', 'covers_ice': True,
     'description': '25% Rabatt auf Flexpreise, 1. Klasse',
     'min_age': None, 'max_age': None, 'is_discount_card': True, 'discount_percent': 25,
     'search_tags': ['bahncard', 'erste klasse', 'first class']},
    {'id': 'bahncard50_1', 'name': 'BahnCard 50 (1. Klasse)', 'category': 'national',
     'price': 515.0, 'period': 'year', 'zone_coverage': 'none', 'covers_ice': True,
     'description': '50% Rabatt auf Flexpreise, 1. Klasse',
     'min_age': None, 'max_age': None, 'is_discount_card': True, 'discount_percent': 50,
     'search_tags': ['bahncard', 'erste klasse', 'first class']},

    {'id': 'einzelfahrausweis_berlin_ab', 'name': 'Einzelfahrausweis Berlin AB', 'category': 'vbb_single',
     'price': 4.00, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Einzelfahrt Berlin AB, 120 Min. gültig mit Umsteigen',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['einzel', 'einzelfahrt', 'berlin', 'ab']},
    {'id': 'einzelfahrausweis_berlin_abc', 'name': 'Einzelfahrausweis Berlin ABC', 'category': 'vbb_single',
     'price': 5.00, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Einzelfahrt Berlin ABC, 120 Min. gültig mit Umsteigen',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['einzel', 'einzelfahrt', 'berlin', 'abc']},
    {'id': 'einzelfahrausweis_berlin_ab_erm', 'name': 'Einzelfahrausweis Berlin AB (ermäßigt)', 'category': 'vbb_single',
     'price': 2.50, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Ermäßigt für Kinder 6-14 Jahre, Berlin AB',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['einzel', 'ermäßigt', 'kinder', 'berlin', 'ab', 'reduziert']},
    {'id': 'einzelfahrausweis_berlin_abc_erm', 'name': 'Einzelfahrausweis Berlin ABC (ermäßigt)', 'category': 'vbb_single',
     'price': 3.50, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Ermäßigt für Kinder 6-14 Jahre, Berlin ABC',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['einzel', 'ermäßigt', 'kinder', 'berlin', 'abc', 'reduziert']},
    {'id': 'kurzstrecke_berlin', 'name': 'Kurzstrecke Berlin', 'category': 'vbb_single',
     'price': 2.80, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '3 S/U-Bahn-Stationen oder 6 Bus/Tram-Stationen',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['kurz', 'kurzstrecke', 'short', 'berlin']},
    {'id': 'kurzstrecke_berlin_erm', 'name': 'Kurzstrecke Berlin (ermäßigt)', 'category': 'vbb_single',
     'price': 2.10, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Kurzstrecke ermäßigt für Kinder 6-14 Jahre',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['kurz', 'kurzstrecke', 'ermäßigt', 'kinder', 'berlin']},
    {'id': '4fahrten_berlin_ab', 'name': '4-Fahrten-Karte Berlin AB', 'category': 'vbb_single',
     'price': 12.40, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '4 Einzelfahrten zum Sparpreis (3,10 €/Fahrt)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['4 fahrten', 'vierer', 'sparpreis', 'berlin', 'ab']},
    {'id': '4fahrten_berlin_abc', 'name': '4-Fahrten-Karte Berlin ABC', 'category': 'vbb_single',
     'price': 16.80, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': '4 Einzelfahrten zum Sparpreis (4,20 €/Fahrt)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['4 fahrten', 'vierer', 'sparpreis', 'berlin', 'abc']},
    {'id': '4fahrten_berlin_ab_erm', 'name': '4-Fahrten-Karte Berlin AB (ermäßigt)', 'category': 'vbb_single',
     'price': 7.40, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '4 Einzelfahrten ermäßigt für Kinder 6-14 (1,85 €/Fahrt)',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['4 fahrten', 'vierer', 'ermäßigt', 'kinder', 'berlin', 'ab']},
    {'id': '4fahrten_berlin_abc_erm', 'name': '4-Fahrten-Karte Berlin ABC (ermäßigt)', 'category': 'vbb_single',
     'price': 11.60, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': '4 Einzelfahrten ermäßigt für Kinder 6-14 (2,90 €/Fahrt)',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['4 fahrten', 'vierer', 'ermäßigt', 'kinder', 'berlin', 'abc']},
    {'id': '4fahrten_kurzstrecke_berlin', 'name': '4-Fahrten-Karte Kurzstrecke Berlin', 'category': 'vbb_single',
     'price': 7.80, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '4 Kurzstreckenfahrten zum Sparpreis (1,95 €/Fahrt)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['4 fahrten', 'kurzstrecke', 'sparpreis', 'berlin']},
    {'id': '4fahrten_kurzstrecke_berlin_erm', 'name': '4-Fahrten-Karte Kurzstrecke Berlin (ermäßigt)', 'category': 'vbb_single',
     'price': 6.20, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '4 Kurzstreckenfahrten ermäßigt (1,55 €/Fahrt)',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['4 fahrten', 'kurzstrecke', 'ermäßigt', 'kinder', 'berlin']},
    {'id': 'erweiterungsfahrausweis_berlin', 'name': 'Erweiterungsfahrausweis Berlin C', 'category': 'vbb_single',
     'price': 2.40, 'period': 'single', 'zone_coverage': 'C', 'covers_ice': False,
     'description': 'Erweiterung eines AB-Tickets auf Zone C',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['erweiterung', 'zone c', 'anschluss', 'berlin']},
    {'id': 'erweiterungsfahrausweis_berlin_erm', 'name': 'Erweiterungsfahrausweis Berlin C (ermäßigt)', 'category': 'vbb_single',
     'price': 1.80, 'period': 'single', 'zone_coverage': 'C', 'covers_ice': False,
     'description': 'Erweiterung ermäßigt für Kinder 6-14',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['erweiterung', 'zone c', 'ermäßigt', 'kinder', 'berlin']},

    {'id': 'einzelfahrausweis_potsdam_ab', 'name': 'Einzelfahrausweis Potsdam AB', 'category': 'vbb_single',
     'price': 3.00, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Einzelfahrt Potsdam AB, 120 Min. gültig mit Umsteigen',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['einzel', 'einzelfahrt', 'potsdam', 'ab']},
    {'id': 'einzelfahrausweis_potsdam_abc', 'name': 'Einzelfahrausweis Potsdam ABC', 'category': 'vbb_single',
     'price': 3.70, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Einzelfahrt Potsdam ABC, 120 Min. gültig mit Umsteigen',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['einzel', 'einzelfahrt', 'potsdam', 'abc']},

    {'id': 'einzelfahrausweis_brb_ab', 'name': 'Einzelfahrausweis Brandenburg/FFO/Cottbus AB', 'category': 'vbb_single',
     'price': 2.70, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Einzelfahrt AB in Brandenburg a.d.H., Frankfurt (Oder) oder Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['einzel', 'brandenburg', 'frankfurt oder', 'cottbus', 'ab']},
    {'id': 'einzelfahrausweis_brb_abc', 'name': 'Einzelfahrausweis Brandenburg/FFO/Cottbus ABC', 'category': 'vbb_single',
     'price': 3.50, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Einzelfahrt ABC in Brandenburg a.d.H., Frankfurt (Oder) oder Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['einzel', 'brandenburg', 'frankfurt oder', 'cottbus', 'abc']},
    {'id': 'einzelfahrausweis_brb_ab_erm', 'name': 'Einzelfahrausweis Brandenburg/FFO/Cottbus AB (ermäßigt)', 'category': 'vbb_single',
     'price': 1.80, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Ermäßigt für Kinder 6-14 in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['einzel', 'ermäßigt', 'kinder', 'brandenburg', 'frankfurt oder', 'cottbus']},
    {'id': 'einzelfahrausweis_brb_abc_erm', 'name': 'Einzelfahrausweis Brandenburg/FFO/Cottbus ABC (ermäßigt)', 'category': 'vbb_single',
     'price': 2.50, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Ermäßigt für Kinder 6-14 in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['einzel', 'ermäßigt', 'kinder', 'brandenburg', 'frankfurt oder', 'cottbus', 'abc']},
    {'id': '4fahrten_brb_ab', 'name': '4-Fahrten-Karte Brandenburg/FFO/Cottbus AB', 'category': 'vbb_single',
     'price': 9.20, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '4 Einzelfahrten in Brandenburg a.d.H./FFO/Cottbus (2,30 €/Fahrt)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['4 fahrten', 'vierer', 'brandenburg', 'frankfurt oder', 'cottbus']},
    {'id': '4fahrten_brb_ab_erm', 'name': '4-Fahrten-Karte Brandenburg/FFO/Cottbus AB (ermäßigt)', 'category': 'vbb_single',
     'price': 6.20, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '4 Einzelfahrten ermäßigt in Brandenburg a.d.H./FFO/Cottbus (1,55 €/Fahrt)',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['4 fahrten', 'vierer', 'ermäßigt', 'kinder', 'brandenburg', 'cottbus']},

    {'id': 'einzelfahrausweis_regional', 'name': 'Einzelfahrausweis VBB Regional (bis 35 km)', 'category': 'vbb_single',
     'price': 8.10, 'period': 'single', 'zone_coverage': 'regional', 'covers_ice': False,
     'description': 'Einzelfahrt im VBB-Verbundgebiet für Strecken bis 35 km',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['einzel', 'regional', 'waben', 'verbund', 'vbb']},

    {'id': 'tageskarte_berlin_ab', 'name': '24-Stunden-Karte Berlin AB', 'category': 'vbb_day',
     'price': 11.20, 'period': 'day', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '24h gültig ab Entwertung, bis zu 3 Kinder (6-14) gratis',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['tages', 'tageskarte', '24 stunden', 'tag', 'berlin', 'ab']},
    {'id': 'tageskarte_berlin_abc', 'name': '24-Stunden-Karte Berlin ABC', 'category': 'vbb_day',
     'price': 12.90, 'period': 'day', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': '24h gültig ab Entwertung, bis zu 3 Kinder (6-14) gratis',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['tages', 'tageskarte', '24 stunden', 'tag', 'berlin', 'abc']},
    {'id': 'tageskarte_berlin_ab_erm', 'name': '24-Stunden-Karte Berlin AB (ermäßigt)', 'category': 'vbb_day',
     'price': 7.40, 'period': 'day', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '24h-Karte ermäßigt für Kinder 6-14 Jahre',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['tages', 'tageskarte', 'ermäßigt', 'kinder', 'berlin', 'ab']},
    {'id': 'tageskarte_berlin_abc_erm', 'name': '24-Stunden-Karte Berlin ABC (ermäßigt)', 'category': 'vbb_day',
     'price': 8.00, 'period': 'day', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': '24h-Karte ermäßigt für Kinder 6-14 Jahre',
     'min_age': 6, 'max_age': 14, 'is_discount_card': False,
     'search_tags': ['tages', 'tageskarte', 'ermäßigt', 'kinder', 'berlin', 'abc']},
    {'id': 'tageskarte_brb_ab', 'name': '24-Stunden-Karte Brandenburg/FFO/Cottbus AB', 'category': 'vbb_day',
     'price': 5.60, 'period': 'day', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '24h Tageskarte in Brandenburg a.d.H./Frankfurt (Oder)/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['tages', 'tageskarte', 'brandenburg', 'cottbus', 'frankfurt oder']},
    {'id': 'tageskarte_brb_abc', 'name': '24-Stunden-Karte Brandenburg/FFO/Cottbus ABC', 'category': 'vbb_day',
     'price': 7.60, 'period': 'day', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': '24h Tageskarte in Brandenburg a.d.H./Frankfurt (Oder)/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['tages', 'tageskarte', 'brandenburg', 'cottbus', 'frankfurt oder', 'abc']},
    {'id': 'tageskarte_vbb_gesamt', 'name': '24-Stunden-Karte VBB-Gesamtnetz', 'category': 'vbb_day',
     'price': 28.50, 'period': 'day', 'zone_coverage': 'all', 'covers_ice': False,
     'description': '24h im gesamten VBB-Verbundgebiet Berlin-Brandenburg',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['tages', 'tageskarte', 'gesamtnetz', 'vbb', 'alles']},
    {'id': 'tageskarte_erweiterung_c', 'name': '24h-Erweiterung Berlin C', 'category': 'vbb_day',
     'price': 5.60, 'period': 'day', 'zone_coverage': 'C', 'covers_ice': False,
     'description': 'Erweiterung einer 24h-Karte AB auf Zone C',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['tages', 'erweiterung', 'zone c', '24 stunden']},

    {'id': 'kleingruppe_berlin_ab', 'name': 'Kleingruppenkarte Berlin AB', 'category': 'vbb_day',
     'price': 35.30, 'period': 'day', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Tageskarte für bis zu 5 Personen, Berlin AB',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['gruppe', 'kleingruppe', '5 personen', 'berlin', 'ab']},
    {'id': 'kleingruppe_berlin_abc', 'name': 'Kleingruppenkarte Berlin ABC', 'category': 'vbb_day',
     'price': 37.70, 'period': 'day', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Tageskarte für bis zu 5 Personen, Berlin ABC',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['gruppe', 'kleingruppe', '5 personen', 'berlin', 'abc']},
    {'id': 'kleingruppe_brb_ab', 'name': 'Kleingruppenkarte Brandenburg/FFO/Cottbus AB', 'category': 'vbb_day',
     'price': 19.40, 'period': 'day', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Tageskarte für bis zu 5 Personen in Brandenburg/FFO/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['gruppe', 'kleingruppe', '5 personen', 'brandenburg', 'cottbus']},
    {'id': 'kleingruppe_brb_abc', 'name': 'Kleingruppenkarte Brandenburg/FFO/Cottbus ABC', 'category': 'vbb_day',
     'price': 21.00, 'period': 'day', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Tageskarte für bis zu 5 Personen in Brandenburg/FFO/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['gruppe', 'kleingruppe', '5 personen', 'brandenburg', 'cottbus', 'abc']},

    {'id': 'umweltkarte_berlin_ab', 'name': 'VBB-Umweltkarte Berlin AB', 'category': 'vbb_month',
     'price': 113.00, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Monatskarte Berlin AB, übertragbar, ab 20 Uhr +1 Erwachsener +3 Kinder',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['monatskarte', 'umweltkarte', 'berlin', 'ab']},
    {'id': 'umweltkarte_berlin_abc', 'name': 'VBB-Umweltkarte Berlin ABC', 'category': 'vbb_month',
     'price': 132.00, 'period': 'month', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Monatskarte Berlin ABC, übertragbar',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['monatskarte', 'umweltkarte', 'berlin', 'abc']},
    {'id': 'umweltkarte_abo_berlin_ab', 'name': 'VBB-Umweltkarte Abo Berlin AB', 'category': 'vbb_month',
     'price': 81.30, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Monatsabo Berlin AB (12 Monate Mindestlaufzeit)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['abo', 'umweltkarte', 'berlin', 'ab', 'abonnement']},
    {'id': 'umweltkarte_abo_berlin_abc', 'name': 'VBB-Umweltkarte Abo Berlin ABC', 'category': 'vbb_month',
     'price': 103.30, 'period': 'month', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Monatsabo Berlin ABC (12 Monate Mindestlaufzeit)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['abo', 'umweltkarte', 'berlin', 'abc', 'abonnement']},
    {'id': 'umweltkarte_brb_ab', 'name': 'VBB-Umweltkarte Brandenburg/FFO/Cottbus AB', 'category': 'vbb_month',
     'price': 52.40, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Monatskarte in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['monatskarte', 'umweltkarte', 'brandenburg', 'cottbus', 'frankfurt oder']},
    {'id': 'umweltkarte_brb_abc', 'name': 'VBB-Umweltkarte Brandenburg/FFO/Cottbus ABC', 'category': 'vbb_month',
     'price': 73.20, 'period': 'month', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Monatskarte in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['monatskarte', 'umweltkarte', 'brandenburg', 'cottbus', 'abc']},
    {'id': 'umweltkarte_abo_brb_ab', 'name': 'VBB-Abo Umwelt Brandenburg/FFO/Cottbus AB', 'category': 'vbb_month',
     'price': 39.90, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Monatsabo in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['abo', 'umweltkarte', 'brandenburg', 'cottbus', 'abonnement']},
    {'id': 'umweltkarte_abo_brb_abc', 'name': 'VBB-Abo Umwelt Brandenburg/FFO/Cottbus ABC', 'category': 'vbb_month',
     'price': 68.40, 'period': 'month', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Monatsabo in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['abo', 'umweltkarte', 'brandenburg', 'cottbus', 'abc', 'abonnement']},

    {'id': 'fahrrad_einzel_berlin_ab', 'name': 'Fahrradkarte Einzelfahrt Berlin AB', 'category': 'vbb_bike',
     'price': 2.70, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Einzelfahrt-Fahrradkarte Berlin AB',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'rad', 'einzelfahrt', 'berlin', 'ab']},
    {'id': 'fahrrad_einzel_berlin_abc', 'name': 'Fahrradkarte Einzelfahrt Berlin ABC', 'category': 'vbb_bike',
     'price': 3.30, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Einzelfahrt-Fahrradkarte Berlin ABC',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'rad', 'einzelfahrt', 'berlin', 'abc']},
    {'id': 'fahrrad_kurzstrecke_berlin', 'name': 'Fahrradkarte Kurzstrecke Berlin', 'category': 'vbb_bike',
     'price': 1.90, 'period': 'single', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Kurzstrecken-Fahrradkarte Berlin AB',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'kurzstrecke', 'berlin']},
    {'id': 'fahrrad_tag_berlin_ab', 'name': 'Fahrrad-Tageskarte Berlin AB', 'category': 'vbb_bike',
     'price': 5.90, 'period': 'day', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '24h Fahrradkarte Berlin AB',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'tageskarte', 'berlin', 'ab']},
    {'id': 'fahrrad_tag_berlin_abc', 'name': 'Fahrrad-Tageskarte Berlin ABC', 'category': 'vbb_bike',
     'price': 6.70, 'period': 'day', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': '24h Fahrradkarte Berlin ABC',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'tageskarte', 'berlin', 'abc']},
    {'id': 'fahrrad_tag_vbb', 'name': 'Fahrrad-Tageskarte VBB-Gesamtnetz', 'category': 'vbb_bike',
     'price': 7.50, 'period': 'day', 'zone_coverage': 'all', 'covers_ice': False,
     'description': '24h Fahrradkarte im gesamten VBB-Netz',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'tageskarte', 'gesamtnetz', 'vbb']},
    {'id': 'fahrrad_einzel_brb', 'name': 'Fahrradkarte Einzelfahrt Brandenburg/FFO/Cottbus', 'category': 'vbb_bike',
     'price': 2.40, 'period': 'single', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Einzelfahrt-Fahrradkarte Brandenburg/FFO/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'brandenburg', 'cottbus']},
    {'id': 'fahrrad_tag_brb', 'name': 'Fahrrad-Tageskarte Brandenburg/FFO/Cottbus', 'category': 'vbb_bike',
     'price': 5.10, 'period': 'day', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': '24h Fahrradkarte Brandenburg/FFO/Cottbus',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'tageskarte', 'brandenburg', 'cottbus']},
    {'id': 'fahrrad_monat_berlin_ab', 'name': 'Fahrrad-Monatskarte Berlin AB', 'category': 'vbb_bike',
     'price': 14.60, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Monatskarte für Fahrradmitnahme Berlin AB',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'monatskarte', 'berlin', 'ab']},
    {'id': 'fahrrad_monat_berlin_abc', 'name': 'Fahrrad-Monatskarte Berlin ABC', 'category': 'vbb_bike',
     'price': 18.20, 'period': 'month', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Monatskarte für Fahrradmitnahme Berlin ABC',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'monatskarte', 'berlin', 'abc']},
    {'id': 'fahrrad_monat_vbb', 'name': 'Fahrrad-Monatskarte VBB-Gesamtnetz', 'category': 'vbb_bike',
     'price': 30.30, 'period': 'month', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Monatskarte für Fahrradmitnahme im gesamten VBB-Netz',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'monatskarte', 'gesamtnetz', 'vbb']},
    {'id': 'fahrrad_einzel_vbb', 'name': 'Fahrradkarte Einzelfahrt VBB-Gesamtnetz', 'category': 'vbb_bike',
     'price': 4.60, 'period': 'single', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Einzelfahrt-Fahrradkarte im gesamten VBB-Netz',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['fahrrad', 'bike', 'einzelfahrt', 'gesamtnetz', 'vbb']},

    {'id': 'berlin_ticket_s', 'name': 'Berlin-Ticket S (Sozialticket)', 'category': 'vbb_social',
     'price': 27.50, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Für Empfänger von Sozialleistungen, Berlin AB',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['sozial', 'sozialticket', 'berlin ticket s', 'transfer', 'hartz', 'bürgergeld']},

    {'id': 'schuelerticket_berlin', 'name': 'Schülerticket Berlin AB', 'category': 'vbb_student',
     'price': 0.0, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Kostenlos für Berliner Schüler*innen (Antrag über Schule)',
     'min_age': None, 'max_age': 20, 'is_discount_card': False,
     'search_tags': ['schüler', 'schueler', 'schule', 'kostenlos', 'gratis', 'berlin']},
    {'id': 'semesterticket', 'name': 'Deutschlandsemesterticket', 'category': 'vbb_student',
     'price': 34.80, 'period': 'month', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Für Studierende, deutschlandweit Nahverkehr (208,80 €/Semester)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['semester', 'student', 'studenten', 'uni', 'hochschule']},
    {'id': 'azubi_ticket', 'name': 'Azubi-Deutschlandticket', 'category': 'vbb_student',
     'price': 37.80, 'period': 'month', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Vergünstigtes Deutschlandticket für Auszubildende (ab März 2026)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['azubi', 'ausbildung', 'lehrling', 'auszubildende']},
    {'id': 'monatskarte_ausbildung_berlin_ab', 'name': 'Monatskarte Ausbildung Berlin AB', 'category': 'vbb_student',
     'price': 74.10, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Ermäßigte Monatskarte für Schüler ab 15, Azubis, Praktikanten',
     'min_age': 15, 'max_age': 25, 'is_discount_card': False,
     'search_tags': ['ausbildung', 'schüler', 'azubi', 'monatskarte', 'berlin', 'ab']},
    {'id': 'monatskarte_ausbildung_berlin_abc', 'name': 'Monatskarte Ausbildung Berlin ABC', 'category': 'vbb_student',
     'price': 95.70, 'period': 'month', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Ermäßigte Monatskarte für Schüler ab 15, Azubis, Praktikanten',
     'min_age': 15, 'max_age': 25, 'is_discount_card': False,
     'search_tags': ['ausbildung', 'schüler', 'azubi', 'monatskarte', 'berlin', 'abc']},
    {'id': 'monatskarte_ausbildung_brb_ab', 'name': 'Monatskarte Ausbildung Brandenburg/FFO/Cottbus AB', 'category': 'vbb_student',
     'price': 40.20, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Ermäßigte Monatskarte Ausbildung in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': 15, 'max_age': 25, 'is_discount_card': False,
     'search_tags': ['ausbildung', 'azubi', 'monatskarte', 'brandenburg', 'cottbus']},
    {'id': 'monatskarte_ausbildung_brb_abc', 'name': 'Monatskarte Ausbildung Brandenburg/FFO/Cottbus ABC', 'category': 'vbb_student',
     'price': 54.30, 'period': 'month', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Ermäßigte Monatskarte Ausbildung in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': 15, 'max_age': 25, 'is_discount_card': False,
     'search_tags': ['ausbildung', 'azubi', 'monatskarte', 'brandenburg', 'cottbus', 'abc']},
    {'id': 'abo_ausbildung_brb_ab', 'name': 'VBB-Abo Ausbildung Brandenburg/FFO/Cottbus AB', 'category': 'vbb_student',
     'price': 30.20, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Ausbildungs-Abo in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': 15, 'max_age': 25, 'is_discount_card': False,
     'search_tags': ['abo', 'ausbildung', 'azubi', 'brandenburg', 'cottbus']},
    {'id': 'abo_ausbildung_brb_abc', 'name': 'VBB-Abo Ausbildung Brandenburg/FFO/Cottbus ABC', 'category': 'vbb_student',
     'price': 43.80, 'period': 'month', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': 'Ausbildungs-Abo in Brandenburg a.d.H./FFO/Cottbus',
     'min_age': 15, 'max_age': 25, 'is_discount_card': False,
     'search_tags': ['abo', 'ausbildung', 'azubi', 'brandenburg', 'cottbus', 'abc']},

    {'id': 'abo_63_brb', 'name': 'VBB-Abo 63vorOrt Brandenburg a.d.H.', 'category': 'vbb_social',
     'price': 34.30, 'period': 'month', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': 'Senioren-Abo ab 63 Jahre in Brandenburg a.d.H.',
     'min_age': 63, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['senior', 'senioren', '63', 'abo', 'brandenburg']},

    {'id': 'bb_ticket', 'name': 'Brandenburg-Berlin-Ticket', 'category': 'regional',
     'price': 36.50, 'period': 'day', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Tageskarte 1-5 Personen, Berlin-Brandenburg, nur Nahverkehr (Automat)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['brandenburg', 'bb ticket', 'gruppentageskarte', 'regional']},
    {'id': 'bb_ticket_nacht', 'name': 'Brandenburg-Berlin-Ticket Nacht', 'category': 'regional',
     'price': 27.00, 'period': 'day', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Nachtticket 18-06 Uhr, 1-5 Personen, Berlin-Brandenburg (Automat)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['brandenburg', 'nacht', 'abend', 'bb ticket']},
    {'id': 'quer_durchs_land', 'name': 'Quer-durchs-Land-Ticket', 'category': 'regional',
     'price': 44.0, 'period': 'day', 'zone_coverage': 'all', 'covers_ice': False,
     'description': 'Deutschlandweiter Nahverkehr, 1 Person (+10 € je Mitfahrer, max 5)',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['quer durchs land', 'deutschlandweit', 'nahverkehr tag']},

    {'id': 'berlin_welcomecard_48', 'name': 'Berlin WelcomeCard 48h AB', 'category': 'tourist',
     'price': 28.50, 'period': 'day', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '48h Fahrschein + Rabatte für Sehenswürdigkeiten',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['welcome', 'tourist', 'besucher', 'sightseeing', '48']},
    {'id': 'berlin_welcomecard_72', 'name': 'Berlin WelcomeCard 72h AB', 'category': 'tourist',
     'price': 37.50, 'period': 'day', 'zone_coverage': 'AB', 'covers_ice': False,
     'description': '72h Fahrschein + Rabatte für Sehenswürdigkeiten',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['welcome', 'tourist', 'besucher', 'sightseeing', '72']},
    {'id': 'berlin_welcomecard_72_abc', 'name': 'Berlin WelcomeCard 72h ABC', 'category': 'tourist',
     'price': 42.90, 'period': 'day', 'zone_coverage': 'ABC', 'covers_ice': False,
     'description': '72h Fahrschein inkl. Zone C + Rabatte für Sehenswürdigkeiten',
     'min_age': None, 'max_age': None, 'is_discount_card': False,
     'search_tags': ['welcome', 'tourist', 'besucher', 'sightseeing', 'abc', 'flughafen']},
]

TICKET_CATEGORY_LABELS = {
    'national': 'Deutschlandweit',
    'vbb_single': 'VBB Einzelfahrten',
    'vbb_day': 'VBB Tageskarten',
    'vbb_month': 'VBB Monatskarten',
    'vbb_bike': 'VBB Fahrradkarten',
    'vbb_social': 'Sozialtickets & Senioren',
    'vbb_student': 'Schüler, Azubis & Studenten',
    'regional': 'Regionaltickets',
    'tourist': 'Touristentickets'
}


def get_user_age(birthday=None, graduation_date=None):
    """Get user age from birthday (precise) or graduation date (estimated, ~18 at Abitur)."""
    today = datetime.now()
    if birthday:
        try:
            bd = datetime.strptime(birthday, '%Y-%m-%d')
            return today.year - bd.year - ((today.month, today.day) < (bd.month, bd.day))
        except (ValueError, TypeError):
            pass
    if graduation_date:
        try:
            grad_year = int(str(graduation_date)[:4])
            return today.year - grad_year + 18
        except (ValueError, TypeError):
            pass
    return None


def search_ticket_catalog(query='', age=None):
    """Search ticket catalog by query and optional age filter."""
    results = TICKET_CATALOG
    if age is not None:
        results = [t for t in results if t.get('max_age') is None or age <= t['max_age']]
        results = [t for t in results if t.get('min_age') is None or age >= t['min_age']]

    if query:
        words = query.lower().split()
        filtered = []
        for t in results:
            searchable = f"{t['name']} {t['description']} {' '.join(t.get('search_tags', []))}".lower()
            if all(w in searchable for w in words):
                filtered.append(t)
        results = filtered

    return results

class VBBService:

    def __init__(self):
        self.locations_cache = self._load_locations_cache()
        self.known_locations = self._load_known_locations()
        self._last_working_api = None

    def _load_locations_cache(self) -> Dict:

        if LOCATIONS_CACHE_FILE.exists():
            try:
                return decrypt_file(LOCATIONS_CACHE_FILE)
            except Exception:
                pass
        return {}

    def _save_locations_cache(self):

        encrypt_file(self.locations_cache, LOCATIONS_CACHE_FILE)

    def _load_known_locations(self) -> Dict:

        if KNOWN_LOCATIONS_FILE.exists():
            try:
                return decrypt_file(KNOWN_LOCATIONS_FILE)
            except Exception:
                pass

        return {
            'home': None,
            'dlrg': None,
            'gym': None,
            'school': None
        }

    def save_known_location(self, name: str, location: Dict) -> Dict:

        self.known_locations[name] = location
        encrypt_file(self.known_locations, KNOWN_LOCATIONS_FILE)
        return {'success': True, 'location': location}

    def get_known_locations(self) -> Dict:

        return {'success': True, 'locations': self.known_locations}

    def delete_known_location(self, name: str) -> Dict:
        if name in self.known_locations:
            del self.known_locations[name]
            encrypt_file(self.known_locations, KNOWN_LOCATIONS_FILE)
            return {'success': True}
        return {'success': False, 'error': 'Ort nicht gefunden'}

    def _api_get(self, path: str, params: dict, timeout: int = 10,
                 preferred_api: str = None) -> requests.Response:
        """Make GET request with automatic fallback between DB and VBB APIs.

        Args:
            preferred_api: If set, try this API base URL first.
        """
        last_error = None
        apis = list(TRANSPORT_APIS)
        if preferred_api and preferred_api in apis:
            apis.remove(preferred_api)
            apis.insert(0, preferred_api)
        for base_url in apis:
            try:
                response = requests.get(
                    f"{base_url}{path}",
                    params=params,
                    timeout=timeout
                )
                response.raise_for_status()
                self._last_working_api = base_url
                return response
            except requests.RequestException as e:
                last_error = e
                logging.warning(f"API {base_url}{path} failed: {e}, trying next...")
                continue
        raise last_error

    def search_location(self, query: str) -> Dict:

        cache_key = query.lower().strip()
        if cache_key in self.locations_cache:
            cached = self.locations_cache[cache_key]

            if cached.get('cached_at'):
                cached_time = datetime.fromisoformat(cached['cached_at'])
                if datetime.now() - cached_time < timedelta(hours=12):
                    return {'success': True, 'locations': cached['results'], 'cached': True}

        try:

            response = self._api_get('/locations', {
                    'query': query,
                    'results': 10,
                    'addresses': True,
                    'poi': True,
                    'stops': True
                })
            locations = response.json()

            normalized = []
            for loc in locations:
                normalized.append({
                    'id': loc.get('id'),
                    'name': loc.get('name'),
                    'type': loc.get('type'),
                    'latitude': loc.get('location', {}).get('latitude') if loc.get('location') else loc.get('latitude'),
                    'longitude': loc.get('location', {}).get('longitude') if loc.get('location') else loc.get('longitude'),
                    'address': loc.get('address'),
                    'products': loc.get('products', {})
                })

            self.locations_cache[cache_key] = {
                'results': normalized,
                'cached_at': datetime.now().isoformat()
            }
            self._save_locations_cache()

            return {'success': True, 'locations': normalized}

        except requests.ConnectionError as e:
            logging.error(f"Transport API connection error: {e}")
            return {'success': False, 'error': 'Keine Verbindung zum Fahrplan-Server. Bitte prüfe deine Internetverbindung.'}
        except requests.Timeout as e:
            logging.error(f"Transport API timeout: {e}")
            return {'success': False, 'error': 'Der Fahrplan-Server antwortet nicht. Bitte versuche es erneut.'}
        except requests.RequestException as e:
            logging.error(f"Transport API error: {e}")
            return {'success': False, 'error': 'Verbindung zum Fahrplan-Service fehlgeschlagen. Bitte versuche es erneut.'}
        except Exception as e:
            logging.error(f"Transport API error: {e}")
            return {'success': False, 'error': 'Ein Fehler ist aufgetreten'}

    def search_nearby_stops(self, latitude: float, longitude: float, radius: int = 1000) -> Dict:

        try:
            response = self._api_get('/stops/nearby', {
                    'latitude': latitude,
                    'longitude': longitude,
                    'distance': radius,
                    'results': 10
                })
            stops = response.json()

            normalized = []
            for stop in stops:
                normalized.append({
                    'id': stop.get('id'),
                    'name': stop.get('name'),
                    'distance': stop.get('distance'),
                    'latitude': stop.get('location', {}).get('latitude'),
                    'longitude': stop.get('location', {}).get('longitude'),
                    'products': stop.get('products', {})
                })

            return {'success': True, 'stops': normalized}

        except requests.ConnectionError as e:
            logging.error(f"Transport API connection error: {e}")
            return {'success': False, 'error': 'Keine Verbindung zum Fahrplan-Server. Bitte prüfe deine Internetverbindung.'}
        except requests.Timeout as e:
            logging.error(f"Transport API timeout: {e}")
            return {'success': False, 'error': 'Der Fahrplan-Server antwortet nicht. Bitte versuche es erneut.'}
        except requests.RequestException as e:
            logging.error(f"Transport API error: {e}")
            return {'success': False, 'error': 'Verbindung zum Fahrplan-Service fehlgeschlagen. Bitte versuche es erneut.'}
        except Exception as e:
            logging.error(f"Transport API error: {e}")
            return {'success': False, 'error': 'Ein Fehler ist aufgetreten'}

    def _build_journey_params(self, from_location: Dict, to_location: Dict,
                              arrival_time: datetime, departure_time: datetime,
                              num_results: int, use_coords: bool = False) -> Optional[Dict]:
        """Build params dict for /journeys API call."""
        params = {
            'results': num_results,
            'stopovers': True,
            'remarks': True,
            'polylines': False,
            'tickets': True
        }

        if not use_coords and from_location.get('id'):
            params['from'] = from_location['id']
        elif from_location.get('latitude') and from_location.get('longitude'):
            params['from.latitude'] = from_location['latitude']
            params['from.longitude'] = from_location['longitude']
            params['from.address'] = from_location.get('name', 'Aktueller Standort')
        elif from_location.get('id'):
            params['from'] = from_location['id']
        else:
            return None

        if not use_coords and to_location.get('id'):
            params['to'] = to_location['id']
        elif to_location.get('latitude') and to_location.get('longitude'):
            params['to.latitude'] = to_location['latitude']
            params['to.longitude'] = to_location['longitude']
            params['to.address'] = to_location.get('name', 'Ziel')
        elif to_location.get('id'):
            params['to'] = to_location['id']
        else:
            return None

        if arrival_time:
            params['arrival'] = arrival_time.isoformat()
        elif departure_time:
            params['departure'] = departure_time.isoformat()
        else:
            params['departure'] = datetime.now().isoformat()

        return params

    def get_route(self, from_location: Dict, to_location: Dict,
                  arrival_time: datetime = None, departure_time: datetime = None,
                  num_results: int = 5) -> Dict:
        try:
            params = self._build_journey_params(
                from_location, to_location, arrival_time, departure_time, num_results
            )
            if params is None:
                return {'success': False, 'error': 'Ungültiger Start- oder Zielort'}

            try:
                response = self._api_get('/journeys', params, timeout=15)
                data = response.json()
            except requests.RequestException:
                # ID-based lookup failed on all APIs (IDs from one API may not
                # work on the other).  Retry with coordinates if available.
                has_coords = (
                    from_location.get('latitude') and from_location.get('longitude')
                    and to_location.get('latitude') and to_location.get('longitude')
                )
                if has_coords and (from_location.get('id') or to_location.get('id')):
                    logging.info("Journey ID lookup failed, retrying with coordinates")
                    coord_params = self._build_journey_params(
                        from_location, to_location, arrival_time, departure_time,
                        num_results, use_coords=True
                    )
                    if coord_params:
                        response = self._api_get('/journeys', coord_params, timeout=15)
                        data = response.json()
                    else:
                        raise
                else:
                    raise

            journeys = data.get('journeys', [])
            routes = []

            for journey in journeys:
                legs = []
                total_duration = 0
                has_delay = False
                max_delay = 0

                for leg in journey.get('legs', []):

                    delay_departure = 0
                    delay_arrival = 0

                    if leg.get('departureDelay'):
                        delay_departure = leg['departureDelay'] // 60
                        if delay_departure > 0:
                            has_delay = True
                            max_delay = max(max_delay, delay_departure)

                    if leg.get('arrivalDelay'):
                        delay_arrival = leg['arrivalDelay'] // 60
                        if delay_arrival > 0:
                            has_delay = True
                            max_delay = max(max_delay, delay_arrival)

                    dep_ts = leg.get('departure') or leg.get('plannedDeparture')
                    arr_ts = leg.get('arrival') or leg.get('plannedArrival')
                    leg_duration = 0
                    if dep_ts and arr_ts:
                        try:
                            d1 = datetime.fromisoformat(dep_ts.replace('Z', '+00:00'))
                            d2 = datetime.fromisoformat(arr_ts.replace('Z', '+00:00'))
                            leg_duration = max(0, int((d2 - d1).total_seconds() / 60))
                        except (ValueError, TypeError):
                            pass

                    leg_info = {
                        'type': 'walk' if leg.get('walking') else 'transit',
                        'departure': {
                            'time': leg.get('departure') or leg.get('plannedDeparture'),
                            'planned_time': leg.get('plannedDeparture'),
                            'delay': delay_departure,
                            'station': leg.get('origin', {}).get('name'),
                            'platform': leg.get('departurePlatform')
                        },
                        'arrival': {
                            'time': leg.get('arrival') or leg.get('plannedArrival'),
                            'planned_time': leg.get('plannedArrival'),
                            'delay': delay_arrival,
                            'station': leg.get('destination', {}).get('name'),
                            'platform': leg.get('arrivalPlatform')
                        },
                        'duration': leg_duration,
                        'distance': leg.get('distance')
                    }

                    if not leg.get('walking'):
                        line = leg.get('line', {})
                        leg_info['line'] = {
                            'name': line.get('name'),
                            'product': line.get('product'),
                            'direction': leg.get('direction'),
                            'operator': line.get('operator', {}).get('name') if line.get('operator') else None
                        }
                        leg_info['trip_id'] = leg.get('tripId')

                        stopovers = leg.get('stopovers', [])
                        leg_info['stops_count'] = max(0, len(stopovers) - 2)

                    occupancy_hint = None
                    load_factor = leg.get('loadFactor')
                    if load_factor:
                        occupancy_map = {
                            'low-to-medium': 'Geringe bis mittlere Auslastung',
                            'medium': 'Mittlere Auslastung',
                            'high': 'Hohe Auslastung',
                            'very-high': 'Sehr hohe Auslastung',
                            'exceptionally-high': 'Außergewöhnlich hohe Auslastung'
                        }
                        occupancy_hint = occupancy_map.get(load_factor, f'Auslastung: {load_factor}')
                    else:
                        for remark in leg.get('remarks', []):
                            remark_text = remark.get('text', '')
                            if any(kw in remark_text.lower() for kw in ['auslastung', 'besetzt', 'voll']):
                                occupancy_hint = remark_text
                                break
                    leg_info['occupancy_hint'] = occupancy_hint

                    legs.append(leg_info)

                first_leg = (journey.get('legs') or [{}])[0]
                last_leg = journey.get('legs', [{}])[-1] if journey.get('legs') else {}
                departure_time_str = first_leg.get('departure') or first_leg.get('plannedDeparture')
                arrival_time_str = last_leg.get('arrival') or last_leg.get('plannedArrival')

                total_duration = 0
                if departure_time_str and arrival_time_str:
                    try:
                        d1 = datetime.fromisoformat(departure_time_str.replace('Z', '+00:00'))
                        d2 = datetime.fromisoformat(arrival_time_str.replace('Z', '+00:00'))
                        total_duration = max(0, int((d2 - d1).total_seconds() / 60))
                    except (ValueError, TypeError):
                        total_duration = sum(leg.get('duration', 0) for leg in legs)

                tickets_data = journey.get('tickets', [])
                parsed_tickets = []
                cheapest_price = None

                for ticket_cat in tickets_data:
                    cat_name = ticket_cat.get('name', '')
                    cat_desc = ticket_cat.get('description', '')
                    for sub_ticket in ticket_cat.get('tickets', []):
                        price_obj = sub_ticket.get('price', {})
                        amount_cents = price_obj.get('amount')
                        if amount_cents is not None:
                            amount_eur = amount_cents / 100.0
                            parsed_tickets.append({
                                'category': cat_name,
                                'name': sub_ticket.get('name', ''),
                                'price': amount_eur,
                                'description': cat_desc
                            })
                            if 'Einzelfahrausweis' in cat_name and 'Regeltarif' in sub_ticket.get('name', ''):
                                cheapest_price = amount_eur
                            elif cheapest_price is None and 'Einzelfahrausweis' in cat_name:
                                cheapest_price = amount_eur

                if cheapest_price is None and parsed_tickets:
                    cheapest_price = min(t['price'] for t in parsed_tickets)

                tariff_zone = tickets_data[0].get('description', '') if tickets_data else None

                routes.append({
                    'departure': departure_time_str,
                    'arrival': arrival_time_str,
                    'duration': total_duration,
                    'transfers': max(0, len([leg for leg in legs if leg['type'] == 'transit']) - 1),
                    'legs': legs,
                    'has_delay': has_delay,
                    'max_delay': max_delay,
                    'price': cheapest_price,
                    'price_unavailable': cheapest_price is None and not parsed_tickets,
                    'tickets': parsed_tickets,
                    'tariff_zone': tariff_zone
                })

            long_distance_products = {'nationalExpress', 'national', 'nationalExp'}
            needs_db_price = []
            for r in routes:
                if r.get('price_unavailable') and r.get('legs'):
                    needs_db_price.append(r)
                elif r.get('legs'):
                    has_long_distance = any(
                        leg.get('line', {}).get('product') in long_distance_products
                        for leg in r['legs'] if leg.get('type') == 'transit'
                    )
                    if has_long_distance:
                        needs_db_price.append(r)

            if needs_db_price:
                first = needs_db_price[0]
                first_station = first['legs'][0].get('departure', {}).get('station', '')
                last_station = first['legs'][-1].get('arrival', {}).get('station', '')
                dep_time = first.get('departure')
                if first_station and last_station and dep_time:
                    db_connections = self.get_db_prices(first_station, last_station, dep_time)
                    if db_connections:
                        self._match_db_prices(needs_db_price, db_connections)

                    still_missing = [r for r in needs_db_price
                                     if r.get('price_unavailable', True) and r.get('departure')]
                    if still_missing and len(still_missing) < len(needs_db_price):
                        later_dep = still_missing[0].get('departure')
                        if later_dep:
                            db_connections2 = self.get_db_prices(
                                first_station, last_station, later_dep)
                            if db_connections2:
                                self._match_db_prices(still_missing, db_connections2)

            routes = self.score_routes(routes)

            return {
                'success': True,
                'routes': routes,
                'from': from_location.get('name', 'Start'),
                'to': to_location.get('name', 'Ziel')
            }

        except requests.ConnectionError as e:
            logging.error(f"Transport API connection error: {e}")
            return {'success': False, 'error': 'Keine Verbindung zum Fahrplan-Server. Bitte prüfe deine Internetverbindung.'}
        except requests.Timeout as e:
            logging.error(f"Transport API timeout: {e}")
            return {'success': False, 'error': 'Der Fahrplan-Server antwortet nicht. Bitte versuche es erneut.'}
        except requests.RequestException as e:
            logging.error(f"Transport API error: {e}")
            return {'success': False, 'error': 'Verbindung zum Fahrplan-Service fehlgeschlagen. Bitte versuche es erneut.'}
        except Exception as e:
            logging.error(f"Transport API error: {e}")
            return {'success': False, 'error': 'Ein Fehler ist aufgetreten'}

    def score_routes(self, routes: list, personalized_weights: dict = None) -> list:
        if not routes:
            return routes

        w_speed = 0.35
        w_transfer = 0.30
        w_delay = 0.25
        w_walk = 0.10
        if personalized_weights:
            w_speed = personalized_weights.get('speed', w_speed)
            w_transfer = personalized_weights.get('transfers', w_transfer)
            w_delay = personalized_weights.get('delay', w_delay)
            w_walk = personalized_weights.get('walk', w_walk)

        durations = [r['duration'] for r in routes if r.get('duration')]
        transfers_list = [r['transfers'] for r in routes if r.get('transfers') is not None]
        delays = [r.get('max_delay', 0) for r in routes]
        prices = [r['price'] for r in routes if r.get('price') is not None]

        min_dur = min(durations) if durations else 0
        max_dur = max(durations) if durations else 1
        dur_range = max_dur - min_dur if max_dur != min_dur else 1

        min_transfers = min(transfers_list) if transfers_list else 0
        max_transfers = max(transfers_list) if transfers_list else 0
        transfer_range = max_transfers - min_transfers if max_transfers != min_transfers else 1

        max_delay_val = max(delays) if delays else 0
        delay_range = max_delay_val if max_delay_val > 0 else 1

        for route in routes:
            speed_score = 1.0 - ((route['duration'] - min_dur) / dur_range) if dur_range > 0 else 1.0
            transfers = route.get('transfers', 0)
            transfer_score = 1.0 - ((transfers - min_transfers) / transfer_range) if transfer_range > 0 else 1.0
            delay_score = 1.0 - (route.get('max_delay', 0) / delay_range) if delay_range > 0 else 1.0

            total_walk = sum(
                leg.get('distance', 0) or 0
                for leg in route.get('legs', [])
                if leg.get('type') == 'walk'
            )
            walk_score = max(0, 1.0 - (total_walk / 2000))

            score = w_speed * speed_score + w_transfer * transfer_score + w_delay * delay_score + w_walk * walk_score
            route['score'] = round(score, 3)

            reasons = []
            if speed_score >= 0.9:
                reasons.append('Schnellste')
            if transfer_score >= 0.9 and transfers <= 1:
                reasons.append('Wenig Umstiege')
            if delay_score >= 0.9 and not route.get('has_delay'):
                reasons.append('Pünktlich')
            if route.get('price') and prices and route['price'] == min(prices):
                reasons.append('Günstigste')

            route['recommendation_reason'] = reasons[0] if reasons else None

        routes.sort(key=lambda r: r.get('score', 0), reverse=True)

        if routes:
            routes[0]['recommended'] = True

        return routes

    def get_route_to_event(self, event: Dict, current_location: Dict,
                          buffer_minutes: int = 15) -> Dict:
        if not event.get('location'):
            return {'success': False, 'error': 'Event hat keinen Ort'}

        location_search = self.search_location(event['location'])
        if not location_search.get('success') or not location_search.get('locations'):
            return {'success': False, 'error': f"Ort nicht gefunden: {event['location']}"}

        destination = location_search['locations'][0]

        event_start = event.get('start')
        if isinstance(event_start, str):
            try:

                for fmt in ['%Y-%m-%dT%H:%M:%S%z', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d %H:%M']:
                    try:
                        event_start = datetime.strptime(event_start.replace('Z', '+00:00'), fmt)
                        break
                    except ValueError:
                        continue
                else:

                    event_start = datetime.strptime(event_start[:10], '%Y-%m-%d')
                    event_start = event_start.replace(hour=9, minute=0)
            except Exception:
                return {'success': False, 'error': 'Ungültiges Datum'}

        arrival_time = event_start - timedelta(minutes=buffer_minutes)

        routes = self.get_route(
            from_location=current_location,
            to_location=destination,
            arrival_time=arrival_time,
            num_results=3
        )

        if routes.get('success'):
            routes['event'] = {
                'title': event.get('title') or event.get('summary'),
                'start': event_start.isoformat() if isinstance(event_start, datetime) else str(event_start),
                'location': event['location'],
                'buffer_minutes': buffer_minutes
            }

        return routes

    def get_departures(self, stop_id: str, duration: int = 30) -> Dict:

        try:
            response = self._api_get(f'/stops/{stop_id}/departures', {
                    'duration': duration,
                    'results': 20,
                    'remarks': True,
                    'language': 'de'
                })
            data = response.json()

            dep_list = data.get('departures', data) if isinstance(data, dict) else data
            if not isinstance(dep_list, list):
                dep_list = []

            departures = []
            for dep in dep_list:
                delay_sec = dep.get('delay') or 0
                delay = delay_sec // 60 if delay_sec else 0

                raw_remarks = dep.get('remarks', [])
                clean_remarks = []
                occupancy = None
                features = []
                for r in raw_remarks:
                    text = r.get('text', '')
                    if not text:
                        continue
                    text = re.sub(r'<[^<>]+>', '', text).strip()
                    text = re.sub(r'\s+', ' ', text)
                    rtype = r.get('type', '')
                    code = r.get('code', '')
                    summary = r.get('summary', '')
                    display = summary if summary and len(summary) < len(text) else text
                    if code == 'bicycle-conveyance' or 'Fahrrad' in text or 'fahrrad' in text.lower():
                        features.append('Fahrradmitnahme')
                    elif any(kw in text.lower() for kw in ['auslastung', 'load', 'besetzt']):
                        occupancy = display
                    elif rtype == 'warning' or r.get('priority', 999) < 100:
                        clean_remarks.append(display)
                    elif rtype == 'status' and ('cancelled' in text.lower() or 'fällt aus' in text.lower()):
                        clean_remarks.append(display)

                departures.append({
                    'time': dep.get('when') or dep.get('plannedWhen'),
                    'planned_time': dep.get('plannedWhen'),
                    'delay': delay,
                    'line': dep.get('line', {}).get('name'),
                    'product': dep.get('line', {}).get('product'),
                    'direction': dep.get('direction'),
                    'platform': dep.get('platform'),
                    'cancelled': dep.get('cancelled', False),
                    'remarks': clean_remarks,
                    'occupancy': occupancy,
                    'features': list(dict.fromkeys(features))
                })

            return {'success': True, 'departures': departures, 'stop_id': stop_id}

        except requests.ConnectionError as e:
            logging.error(f"Transport API connection error for stop {stop_id}: {e}")
            return {'success': False, 'error': 'Keine Verbindung zum Fahrplan-Server. Bitte prüfe deine Internetverbindung.'}
        except requests.Timeout as e:
            logging.error(f"Transport API timeout for stop {stop_id}: {e}")
            return {'success': False, 'error': 'Der Fahrplan-Server antwortet nicht. Bitte versuche es erneut.'}
        except requests.RequestException as e:
            logging.error(f"Transport API error for stop {stop_id}: {e}")
            return {'success': False, 'error': 'Verbindung zum Fahrplan-Service fehlgeschlagen. Bitte versuche es erneut.'}
        except Exception as e:
            logging.error(f"Transport API error for stop {stop_id}: {e}")
            return {'success': False, 'error': 'Ein Fehler ist aufgetreten'}

    def _match_db_prices(self, routes: list, db_connections: list):
        """Match DB API connections to VBB routes by departure time and apply prices."""
        for route in routes:
            route_dep = route.get('departure', '')
            if not route_dep or not route.get('price_unavailable', True):
                continue
            best_match = None
            best_diff = 999999
            for db_conn in db_connections:
                try:
                    vbb_str = route_dep[:19]
                    db_str = db_conn['departure'][:19]
                    vbb_dt = datetime.fromisoformat(vbb_str)
                    db_dt = datetime.fromisoformat(db_str)
                    diff = abs((db_dt - vbb_dt).total_seconds())
                    if diff < best_diff:
                        best_diff = diff
                        best_match = db_conn
                except (ValueError, TypeError):
                    continue
            if best_match and best_diff <= 300:
                route['price'] = best_match['price']
                route['price_source'] = 'db'
                route['price_unavailable'] = False
                if best_match.get('ctxRecon'):
                    route['ctxRecon'] = best_match['ctxRecon']

    def _resolve_db_station(self, name: str) -> Optional[str]:
        """Resolve a station name to a DB internal API lid string."""
        try:
            res = requests.get(f"{DB_INTERNAL_API}/reiseloesung/orte",
                params={'suchbegriff': name}, timeout=5,
                headers={'Accept': 'application/json'})
            if not res.ok:
                return None
            data = res.json()
            if data and isinstance(data, list) and len(data) > 0:
                return data[0].get('id')
            return None
        except Exception as e:
            logging.debug(f"DB station resolve failed for '{name}': {e}")
            return None

    def get_db_prices(self, from_name: str, to_name: str, departure_time: str) -> list:
        """Fetch per-connection prices from DB internal API (same as bahn.de uses).

        Returns a list of dicts: [{'departure': str, 'arrival': str, 'price': float}, ...]
        Each entry represents one connection with its accurate price from bahn.de.
        """
        try:
            from_lid = self._resolve_db_station(from_name)
            to_lid = self._resolve_db_station(to_name)
            if not from_lid or not to_lid:
                logging.debug(f"DB price: could not resolve stations '{from_name}' / '{to_name}'")
                return []

            dep_iso = departure_time
            try:
                dt = datetime.fromisoformat(departure_time.replace('Z', '+00:00'))
                dep_iso = dt.strftime('%Y-%m-%dT%H:%M:%S')
            except (ValueError, TypeError):
                pass

            payload = {
                "abfahrtsHalt": from_lid,
                "ankunftsHalt": to_lid,
                "anfrageZeitpunkt": dep_iso,
                "ankunftSuche": "ABFAHRT",
                "klasse": "KLASSE_2",
                "reisende": [{
                    "typ": "ERWACHSENER",
                    "anzahl": 1,
                    "alter": [],
                    "ermaessigungen": [
                        {"art": "KEINE_ERMAESSIGUNG", "klasse": "KLASSENLOS"}
                    ]
                }],
                "produktgattungen": [
                    "ICE", "EC_IC", "IR", "REGIONAL", "SBAHN",
                    "BUS", "SCHIFF", "UBAHN", "TRAM", "ANRUFPFLICHTIG"
                ],
                "schnelleVerbindungen": True,
                "sitzplatzOnly": False,
                "bikeCarriage": False,
                "reservierungsKontingenteVorhanden": False
            }

            headers = {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Accept-Language': 'de-DE',
            }

            res = requests.post(f"{DB_INTERNAL_API}/angebote/fahrplan",
                json=payload, headers=headers, timeout=15)

            if res.status_code not in (200, 201):
                logging.debug(f"DB price API returned {res.status_code}")
                return []

            data = res.json()
            connections = data.get('verbindungen', [])
            if not connections:
                return []

            results = []
            for conn in connections:
                price_info = conn.get('angebotsPreis')
                if not price_info or price_info.get('betrag') is None:
                    continue

                legs = conn.get('verbindungsAbschnitte', [])
                if not legs:
                    continue

                dep = legs[0].get('abfahrtsZeitpunkt', '')
                arr = legs[-1].get('ankunftsZeitpunkt', '')

                results.append({
                    'departure': dep,
                    'arrival': arr,
                    'price': price_info['betrag'],
                    'is_partial': conn.get('hasTeilpreis', False),
                    'ctxRecon': conn.get('ctxRecon'),
                })

            logging.debug(f"DB price API returned {len(results)} connections with prices")
            return results
        except Exception as e:
            logging.debug(f"DB price fallback failed: {e}")
            return []

    def get_ticket_offers(self, ctx_recon: str) -> Dict:
        """Fetch detailed ticket offers for a specific connection using DB recon API."""
        try:
            headers = {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Accept-Language': 'de-DE',
            }

            payload = {
                "ctxRecon": ctx_recon,
                "klasse": "KLASSE_2",
                "reisende": [{
                    "typ": "ERWACHSENER",
                    "anzahl": 1,
                    "alter": [],
                    "ermaessigungen": [
                        {"art": "KEINE_ERMAESSIGUNG", "klasse": "KLASSENLOS"}
                    ]
                }]
            }

            res = requests.post(f"{DB_INTERNAL_API}/angebote/recon",
                json=payload, headers=headers, timeout=15)

            if res.status_code not in (200, 201):
                logging.debug(f"DB recon API returned {res.status_code}")
                return {'success': False, 'error': 'Ticketangebote nicht verfügbar'}

            data = res.json()

            verbindungen = data.get('verbindungen', [])
            reise_angebote = verbindungen[0].get('reiseAngebote', []) if verbindungen else []

            offers = []
            seen = set()
            for angebot in reise_angebote:
                name = angebot.get('name', '')
                klasse = angebot.get('klasse', '')
                preis = angebot.get('preis', {})
                betrag = preis.get('betrag')

                if betrag is None:
                    continue

                if 'Probe BahnCard' in name or 'BahnCard' in name:
                    continue
                is_bc_discount = any(
                    'BahnCard' in kond.get('textKurz', '') or 'BahnCard' in kond.get('textLang', '')
                    for kond in angebot.get('konditionsAnzeigen', [])
                )
                if is_bc_discount:
                    continue

                key = f"{name}_{klasse}"
                if key in seen:
                    continue
                seen.add(key)

                conditions = []
                for kond in angebot.get('konditionsAnzeigen', []):
                    header = kond.get('anzeigeUeberschrift', '')
                    short_text = kond.get('textKurz', '')
                    if header and short_text:
                        conditions.append({
                            'label': header,
                            'text': short_text
                        })

                buchbar = True
                hinfahrt = angebot.get('hinfahrt', {})
                for fa in hinfahrt.get('fahrtAngebote', []):
                    if fa.get('buchbarkeit') != 'BUCHBAR':
                        buchbar = False

                sitzplatz = None
                for sp in hinfahrt.get('sitzplatzAngebote', []):
                    if sp.get('reservierungVerfuegbar'):
                        sp_preis = sp.get('angebot', {}).get('preis', {}).get('betrag')
                        if sp_preis is not None:
                            sitzplatz = sp_preis

                class_label = '1. Klasse' if klasse == 'KLASSE_1' else '2. Klasse'

                offers.append({
                    'name': name,
                    'class': class_label,
                    'class_key': klasse,
                    'price': betrag,
                    'conditions': conditions,
                    'bookable': buchbar,
                    'seat_reservation_price': sitzplatz,
                })

            offers.sort(key=lambda o: (0 if o['class_key'] == 'KLASSE_2' else 1, o['price']))

            return {
                'success': True,
                'offers': offers
            }
        except Exception as e:
            logging.error(f"DB recon error: {e}")
            return {'success': False, 'error': 'Ticketangebote konnten nicht geladen werden'}

    def check_delays_for_route(self, route: Dict) -> Dict:

        delays = []
        total_delay = 0

        for leg in route.get('legs', []):
            if leg.get('type') != 'transit':
                continue

            departure = leg.get('departure', {})
            if departure.get('delay', 0) > 0:
                delays.append({
                    'station': departure.get('station'),
                    'line': leg.get('line', {}).get('name'),
                    'delay_minutes': departure.get('delay'),
                    'type': 'departure'
                })
                total_delay = max(total_delay, departure.get('delay', 0))

            arrival = leg.get('arrival', {})
            if arrival.get('delay', 0) > 0:
                delays.append({
                    'station': arrival.get('station'),
                    'line': leg.get('line', {}).get('name'),
                    'delay_minutes': arrival.get('delay'),
                    'type': 'arrival'
                })
                total_delay = max(total_delay, arrival.get('delay', 0))

        return {
            'success': True,
            'has_delays': len(delays) > 0,
            'delays': delays,
            'max_delay_minutes': total_delay
        }

    def format_route_summary(self, route: Dict) -> str:

        if not route.get('legs'):
            return "Keine Route gefunden"

        parts = []
        for leg in route['legs']:
            if leg['type'] == 'walk':
                if leg.get('distance'):
                    parts.append(f"🚶 {leg['distance']}m zu Fuß")
                else:
                    parts.append(f"🚶 {leg['duration']} Min. zu Fuß")
            else:
                line = leg.get('line', {})
                product = line.get('product', '')
                name = line.get('name', '')

                emoji = {
                    'suburban': '🚆',
                    'subway': '🚇',
                    'tram': '🚊',
                    'bus': '🚌',
                    'ferry': '⛴️',
                    'express': '🚄',
                    'regional': '🚂'
                }.get(product, '🚃')

                direction = line.get('direction', '')
                if direction and len(direction) > 20:
                    direction = direction[:20] + '...'

                parts.append(f"{emoji} {name} → {direction}")

        summary = " → ".join(parts)

        duration = route.get('duration', 0)
        transfers = route.get('transfers', 0)

        timing = f"⏱️ {duration} Min."
        if transfers > 0:
            timing += f", {transfers} Umstieg{'e' if transfers > 1 else ''}"

        if route.get('has_delay'):
            timing += f" ⚠️ +{route.get('max_delay', 0)} Min. Verspätung"

        return f"{summary}\n{timing}"

    def check_ticket_coverage(self, route: Dict, user_tickets: List[Dict], travel_date: str = None) -> Dict:
        """Check if user's tickets cover the given route."""
        if not user_tickets:
            return {'covered': False, 'reason': 'no_tickets'}

        tariff_zone = route.get('tariff_zone') or ''
        required_zones = set()
        for zone_letter in ['A', 'B', 'C']:
            if zone_letter in tariff_zone.upper():
                required_zones.add(zone_letter)

        has_ice_ic = any(
            leg.get('line', {}).get('product') in ('express', 'nationalExpress', 'national')
            for leg in route.get('legs', [])
            if leg.get('type') == 'transit'
        )

        if travel_date is None:
            dep = route.get('departure')
            if dep:
                try:
                    travel_date = datetime.fromisoformat(dep.replace('Z', '+00:00')).strftime('%Y-%m-%d')
                except (ValueError, TypeError):
                    travel_date = datetime.now().strftime('%Y-%m-%d')
            else:
                travel_date = datetime.now().strftime('%Y-%m-%d')

        zone_coverage_map = {
            'all': {'A', 'B', 'C'},
            'ABC': {'A', 'B', 'C'},
            'AB': {'A', 'B'},
            'BC': {'B', 'C'},
            'A': {'A'},
            'B': {'B'},
            'C': {'C'}
        }

        for ticket in user_tickets:
            if not ticket.get('is_active', True):
                continue

            valid_from = ticket.get('valid_from')
            valid_until = ticket.get('valid_until')
            if valid_from and travel_date < valid_from:
                continue
            if valid_until and travel_date > valid_until:
                if not ticket.get('auto_renews'):
                    continue

            coverage = zone_coverage_map.get(ticket.get('zone_coverage', ''), set())

            if ticket.get('ticket_type') == 'deutschlandticket':
                if has_ice_ic:
                    return {
                        'covered': False,
                        'insufficient_reason': 'Das Deutschlandticket gilt nicht für ICE/IC-Züge.',
                        'needed_ticket': 'ICE/IC-Fahrkarte',
                        'covering_ticket': None
                    }
                return {
                    'covered': True,
                    'covering_ticket': ticket.get('ticket_name', 'Deutschlandticket'),
                    'expires_soon': self._ticket_expires_soon(ticket, travel_date)
                }

            if required_zones and required_zones.issubset(coverage):
                if not has_ice_ic:
                    return {
                        'covered': True,
                        'covering_ticket': ticket.get('ticket_name'),
                        'expires_soon': self._ticket_expires_soon(ticket, travel_date)
                    }

        if required_zones:
            zone_str = ''.join(sorted(required_zones))
            return {
                'covered': False,
                'insufficient_reason': f'Kein gültiges Ticket für Zone {zone_str}.',
                'needed_ticket': f'Einzelfahrausweis {zone_str}' if len(required_zones) <= 3 else 'Fahrkarte',
                'covering_ticket': None
            }
        return {
            'covered': False,
            'insufficient_reason': 'Tarifzone konnte nicht ermittelt werden.',
            'needed_ticket': None,
            'covering_ticket': None
        }

    def _ticket_expires_soon(self, ticket: Dict, travel_date: str) -> bool:
        """Check if ticket expires within 7 days of travel date."""
        valid_until = ticket.get('valid_until')
        if not valid_until or ticket.get('auto_renews'):
            return False
        try:
            expire = datetime.strptime(valid_until, '%Y-%m-%d')
            travel = datetime.strptime(travel_date, '%Y-%m-%d')
            return 0 <= (expire - travel).days <= 7
        except (ValueError, TypeError):
            return False

    def get_trip_updates(self, trip_id: str) -> Dict:
        """Get real-time updates for a specific trip."""
        try:
            response = self._api_get(f'/trips/{trip_id}',
                {'stopovers': True, 'remarks': True})
            data = response.json()

            trip = data.get('trip', data)
            stopovers = trip.get('stopovers', [])

            delays = []
            cancelled = trip.get('cancelled', False)

            for stop in stopovers:
                dep_delay = (stop.get('departureDelay') or 0) // 60
                arr_delay = (stop.get('arrivalDelay') or 0) // 60
                if dep_delay >= 2 or arr_delay >= 2 or stop.get('cancelled'):
                    delays.append({
                        'station': stop.get('stop', {}).get('name'),
                        'departure_delay': dep_delay,
                        'arrival_delay': arr_delay,
                        'cancelled': stop.get('cancelled', False),
                        'departure': stop.get('departure') or stop.get('plannedDeparture'),
                        'arrival': stop.get('arrival') or stop.get('plannedArrival')
                    })

            remarks = [r.get('text') for r in trip.get('remarks', []) if r.get('text')]

            return {
                'success': True,
                'trip_id': trip_id,
                'cancelled': cancelled,
                'delays': delays,
                'remarks': remarks,
                'line': trip.get('line', {}).get('name'),
                'direction': trip.get('direction')
            }

        except requests.RequestException as e:
            logging.error(f"VBB trip update error for {trip_id}: {e}")
            return {'success': False, 'error': 'Echtzeit-Daten nicht verfügbar'}
        except Exception as e:
            logging.error(f"VBB trip update error for {trip_id}: {e}")
            return {'success': False, 'error': 'Ein Fehler ist aufgetreten'}

    def check_route_connections(self, route_data: Dict) -> Dict:
        """Check if all connections in a monitored route are still reachable."""
        legs = route_data.get('legs', [])
        transit_legs = [leg for leg in legs if leg.get('type') == 'transit']

        connection_issues = []

        for i in range(len(transit_legs) - 1):
            current_leg = transit_legs[i]
            next_leg = transit_legs[i + 1]

            trip_id = current_leg.get('trip_id')
            if not trip_id:
                continue

            trip_data = self.get_trip_updates(trip_id)
            if not trip_data.get('success'):
                continue

            arr_station = current_leg.get('arrival', {}).get('station', '')
            current_delay = 0
            for delay_info in trip_data.get('delays', []):
                if delay_info.get('station') and arr_station in delay_info['station']:
                    current_delay = delay_info.get('arrival_delay', 0)
                    break

            if trip_data.get('cancelled'):
                connection_issues.append({
                    'type': 'cancelled',
                    'line': current_leg.get('line', {}).get('name'),
                    'station': arr_station,
                    'message': f"{current_leg.get('line', {}).get('name', 'Verbindung')} fällt aus"
                })
                continue

            current_arr = current_leg.get('arrival', {}).get('time')
            next_dep = next_leg.get('departure', {}).get('time')

            if current_arr and next_dep:
                try:
                    arr_time = datetime.fromisoformat(current_arr.replace('Z', '+00:00'))
                    dep_time = datetime.fromisoformat(next_dep.replace('Z', '+00:00'))
                    buffer_minutes = (dep_time - arr_time).total_seconds() / 60
                    effective_buffer = buffer_minutes - current_delay

                    if effective_buffer < 0:
                        transfer_station = next_leg.get('departure', {}).get('station', '')
                        connection_issues.append({
                            'type': 'missed',
                            'line': current_leg.get('line', {}).get('name'),
                            'next_line': next_leg.get('line', {}).get('name'),
                            'station': transfer_station,
                            'delay': current_delay,
                            'message': f"Umstieg in {transfer_station} gefährdet (+{current_delay} Min.)"
                        })
                    elif effective_buffer < 2 and current_delay >= 2:
                        transfer_station = next_leg.get('departure', {}).get('station', '')
                        connection_issues.append({
                            'type': 'tight',
                            'line': current_leg.get('line', {}).get('name'),
                            'next_line': next_leg.get('line', {}).get('name'),
                            'station': transfer_station,
                            'delay': current_delay,
                            'buffer': effective_buffer,
                            'message': f"Umstieg in {transfer_station} knapp (+{current_delay} Min.)"
                        })
                except (ValueError, TypeError):
                    pass

        return {
            'success': True,
            'has_issues': len(connection_issues) > 0,
            'issues': connection_issues
        }


vbb_service = VBBService()

def get_vbb_service() -> VBBService:

    return vbb_service
