# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import subprocess
import logging
import shutil
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from pathlib import Path
import re

from .crypto_utils import encrypt_file, decrypt_file

try:
    import EventKit
    EVENTKIT_AVAILABLE = True
except ImportError:
    EVENTKIT_AVAILABLE = False

try:
    import caldav
    CALDAV_AVAILABLE = True
except ImportError:
    CALDAV_AVAILABLE = False

import socket
from urllib.parse import urlparse
from .paths import DATA_DIR
from . import brand

CALDAV_ACCOUNTS_FILE = DATA_DIR / 'caldav_accounts.json'
CALDAV_TIMEOUT = 15

_METADATA_IPS = {'169.254.169.254', 'fd00:ec2::254'}


def _check_blocked_ip(addr) -> Optional[str]:
    # ::ffff:127.0.0.1 and ::ffff:169.254.169.254 are the same destinations in
    # IPv6 clothing, and is_loopback only unwraps them on newer CPython.
    mapped = getattr(addr, 'ipv4_mapped', None)
    if mapped is not None:
        addr = mapped
    if addr.is_loopback or addr.is_unspecified:
        return "Connection to loopback address is not allowed"
    if str(addr) in _METADATA_IPS:
        return "Connection to cloud metadata endpoint is not allowed"
    return None


def _validate_caldav_url(url: str) -> Optional[str]:
    """Validate CalDAV URL to prevent SSRF. Returns error message or None if valid.

    Blocks loopback, unspecified (0.0.0.0), and cloud metadata endpoints.
    Allows RFC 1918 / link-local so self-hosted CalDAV servers on a LAN
    (Synology, Nextcloud, school IServ) remain reachable.
    """
    import ipaddress as _ipaddress
    try:
        parsed = urlparse(url)
    except Exception:
        return "Invalid URL"
    if parsed.scheme not in ('http', 'https'):
        return "Only http:// and https:// URLs are allowed"
    hostname = parsed.hostname or ''
    if not hostname:
        return "Invalid URL: no hostname"
    blocked_hosts = {'localhost', '127.0.0.1', '0.0.0.0', '169.254.169.254', '[::1]', '::1'}
    if hostname in blocked_hosts:
        return "Connection to localhost or metadata endpoints is not allowed"
    try:
        err = _check_blocked_ip(_ipaddress.ip_address(hostname))
        if err:
            return err
    except ValueError:
        pass
    try:
        resolved = socket.getaddrinfo(hostname, None, socket.AF_UNSPEC, socket.SOCK_STREAM)
        for _family, _type, _proto, _canonname, sockaddr in resolved:
            ip_str = sockaddr[0].split('%', 1)[0]
            try:
                err = _check_blocked_ip(_ipaddress.ip_address(ip_str))
                if err:
                    return err
            except ValueError:
                pass
    except socket.gaierror:
        return "Cannot resolve hostname"
    return None

_OLD_CALDAV_FILE = Path(__file__).parent.parent / 'caldav_accounts.json'
if _OLD_CALDAV_FILE.exists() and not CALDAV_ACCOUNTS_FILE.exists():
    CALDAV_ACCOUNTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(_OLD_CALDAV_FILE), str(CALDAV_ACCOUNTS_FILE))

def _escape_ical_value(value: str) -> str:
    """Escape special characters in iCalendar property values per RFC 5545."""
    if not value:
        return ''
    value = str(value)
    value = value.replace('\\', '\\\\')
    value = value.replace('\r\n', '\\n')
    value = value.replace('\n', '\\n')
    value = value.replace('\r', '\\n')
    value = value.replace(';', '\\;')
    value = value.replace(',', '\\,')
    return value

def load_caldav_accounts() -> List[Dict]:
    try:
        return decrypt_file(CALDAV_ACCOUNTS_FILE) or []
    except Exception:
        return []

def save_caldav_accounts(accounts: List[Dict]):
    encrypt_file(accounts, CALDAV_ACCOUNTS_FILE)

def add_caldav_account(name: str, url: str, username: str, password: str, provider: str = 'caldav') -> Dict:

    if not CALDAV_AVAILABLE:
        return {
            "success": False,
            "error": "CalDAV not available. Install with: pip install caldav icalendar"
        }

    provider_urls = {
        'samsung': 'https://caldav.samsung.com/caldav/',
        'icloud': 'https://caldav.icloud.com/',
        'fastmail': 'https://caldav.fastmail.com/dav/calendars/user/{username}/',
        'google': 'https://www.googleapis.com/caldav/v2/{username}/events/',
    }

    if not url and provider in provider_urls:
        url = provider_urls[provider].format(username=username)

    if not url:
        return {"success": False, "error": "CalDAV URL is required"}

    url_error = _validate_caldav_url(url)
    if url_error:
        return {"success": False, "error": url_error}

    try:
        client = caldav.DAVClient(url=url, username=username, password=password, timeout=CALDAV_TIMEOUT)
        principal = client.principal()
        calendars = principal.calendars()

        account = {
            "id": f"caldav_{len(load_caldav_accounts())}_{datetime.now().strftime('%Y%m%d%H%M%S')}",
            "name": name or username,
            "url": url,
            "username": username,
            "password": password,
            "provider": provider,
            "calendars": [{"name": cal.name, "url": str(cal.url)} for cal in calendars]
        }

        accounts = load_caldav_accounts()
        accounts.append(account)
        save_caldav_accounts(accounts)

        return {
            "success": True,
            "account": {
                "id": account["id"],
                "name": account["name"],
                "provider": provider,
                "calendars": account["calendars"]
            }
        }
    except Exception as e:
        logging.error(f"CalDAV connect error: {e}")
        return {"success": False, "error": "Failed to connect to calendar"}

def remove_caldav_account(account_id: str) -> Dict:

    accounts = load_caldav_accounts()
    accounts = [a for a in accounts if a.get('id') != account_id]
    save_caldav_accounts(accounts)
    return {"success": True}

def get_caldav_accounts() -> List[Dict]:

    accounts = load_caldav_accounts()
    return [
        {
            "id": a.get("id"),
            "name": a.get("name"),
            "provider": a.get("provider"),
            "calendars": a.get("calendars", [])
        }
        for a in accounts
    ]

def fetch_caldav_events(account_id: str = None, days_ahead: int = 30,
                        start_date: str = None, end_date: str = None) -> Dict:

    if not CALDAV_AVAILABLE:
        return {
            "success": False,
            "error": "caldav_not_available",
            "message": "CalDAV not available. Install with: pip install caldav icalendar",
            "events": []
        }

    accounts = load_caldav_accounts()
    if account_id:
        accounts = [a for a in accounts if a.get('id') == account_id]

    if not accounts:
        return {"success": True, "events": [], "message": "No CalDAV accounts configured"}

    if start_date and end_date:
        try:
            start = datetime.strptime(start_date, '%Y-%m-%d')
            end = datetime.strptime(end_date, '%Y-%m-%d')
        except ValueError:
            return {"success": False, "error": "Invalid date format", "events": []}
    else:
        start = datetime.now()
        end = start + timedelta(days=days_ahead)

    all_events = []

    for account in accounts:
        try:
            client = caldav.DAVClient(
                url=account['url'],
                username=account['username'],
                password=account['password'],
                timeout=CALDAV_TIMEOUT
            )
            principal = client.principal()
            calendars = principal.calendars()

            for cal in calendars:
                try:

                    events = cal.date_search(start=start, end=end, expand=True)

                    for event in events:
                        try:
                            ical = event.icalendar_component
                            vevent = ical.walk('VEVENT')[0] if ical.walk('VEVENT') else None

                            if not vevent:
                                continue

                            dtstart = vevent.get('dtstart')
                            dtend = vevent.get('dtend')

                            if dtstart:
                                dt = dtstart.dt
                                if hasattr(dt, 'date'):
                                    start_date_str = dt.strftime('%Y-%m-%d')
                                    start_time_str = dt.strftime('%H:%M') if hasattr(dt, 'hour') else ''
                                else:
                                    start_date_str = dt.strftime('%Y-%m-%d')
                                    start_time_str = ''
                            else:
                                continue

                            if dtend:
                                dt = dtend.dt
                                if hasattr(dt, 'date'):
                                    end_date_str = dt.strftime('%Y-%m-%d')
                                    end_time_str = dt.strftime('%H:%M') if hasattr(dt, 'hour') else ''
                                else:
                                    end_date_str = dt.strftime('%Y-%m-%d')
                                    end_time_str = ''
                            else:
                                end_date_str = start_date_str
                                end_time_str = ''

                            provider_colors = {
                                'samsung': '#1428A0',
                                'icloud': '#007AFF',
                                'caldav': '#6366f1'
                            }

                            all_events.append({
                                "id": f"caldav_{str(vevent.get('uid', ''))[:20]}",
                                "title": str(vevent.get('summary', 'No title')),
                                "start_date": start_date_str,
                                "start_time": start_time_str,
                                "end_date": end_date_str,
                                "end_time": end_time_str,
                                "all_day": not start_time_str,
                                "location": str(vevent.get('location', '')),
                                "description": str(vevent.get('description', '')),
                                "calendar": cal.name,
                                "calendar_id": str(cal.url),
                                "calendar_color": provider_colors.get(account.get('provider'), '#6366f1'),
                                "source": account.get('provider', 'caldav'),
                                "account_id": account.get('id')
                            })
                        except Exception:
                            continue
                except Exception:
                    continue
        except Exception:
            continue

    all_events.sort(key=lambda e: (e.get('start_date', ''), e.get('start_time', '00:00')))

    return {"success": True, "events": all_events}

def create_caldav_event(account_id: str, calendar_url: str, title: str,
                        start_date: str, start_time: str = None,
                        end_date: str = None, end_time: str = None,
                        description: str = '', location: str = '') -> Dict:

    if not CALDAV_AVAILABLE:
        return {"success": False, "error": "CalDAV not available"}

    accounts = load_caldav_accounts()
    account = next((a for a in accounts if a.get('id') == account_id), None)

    if not account:
        return {"success": False, "error": "Account not found"}

    url_error = _validate_caldav_url(calendar_url)
    if url_error:
        return {"success": False, "error": url_error}

    account_host = urlparse(account['url']).hostname
    calendar_host = urlparse(calendar_url).hostname
    if not account_host or not calendar_host or account_host.lower() != calendar_host.lower():
        return {"success": False, "error": "Calendar URL does not match account server"}

    try:
        client = caldav.DAVClient(
            url=account['url'],
            username=account['username'],
            password=account['password'],
            timeout=CALDAV_TIMEOUT
        )

        cal = caldav.Calendar(client=client, url=calendar_url)

        uid = f"{datetime.now().strftime('%Y%m%d%H%M%S')}-{brand.NAME.lower()}@local"

        if start_time:
            dtstart = datetime.strptime(f"{start_date} {start_time}", '%Y-%m-%d %H:%M')
            if end_date and end_time:
                dtend = datetime.strptime(f"{end_date} {end_time}", '%Y-%m-%d %H:%M')
            else:
                dtend = dtstart + timedelta(hours=1)
            dtstart_str = dtstart.strftime('%Y%m%dT%H%M%S')
            dtend_str = dtend.strftime('%Y%m%dT%H%M%S')
        else:
            dtstart_str = datetime.strptime(start_date, '%Y-%m-%d').strftime('%Y%m%d')
            if end_date:
                dtend_str = datetime.strptime(end_date, '%Y-%m-%d').strftime('%Y%m%d')
            else:
                dtend_str = dtstart_str

        ical_str = f"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//{brand.NAME}//CalDAV Client//EN
BEGIN:VEVENT
UID:{uid}
DTSTAMP:{datetime.now().strftime('%Y%m%dT%H%M%SZ')}
DTSTART:{dtstart_str}
DTEND:{dtend_str}
SUMMARY:{_escape_ical_value(title)}
DESCRIPTION:{_escape_ical_value(description)}
LOCATION:{_escape_ical_value(location)}
END:VEVENT
END:VCALENDAR"""

        cal.add_event(ical_str)

        return {"success": True, "event_id": uid}
    except Exception as e:
        logging.error(f"CalDAV create event error: {e}")
        return {"success": False, "error": "Calendar error"}

def get_macos_calendar_events_eventkit(days_ahead: int = 14) -> Dict:

    if not EVENTKIT_AVAILABLE:
        return {
            "success": False,
            "error": "eventkit_not_available",
            "message": "EventKit not available. Install with: pip install pyobjc-framework-EventKit",
            "events": []
        }

    try:
        store = EventKit.EKEventStore.alloc().init()

        status = EventKit.EKEventStore.authorizationStatusForEntityType_(EventKit.EKEntityTypeEvent)

        if status == EventKit.EKAuthorizationStatusNotDetermined:

            try:

                store.requestFullAccessToEventsWithCompletion_(lambda granted, error: None)
            except Exception:

                store.requestAccessToEntityType_completion_(
                    EventKit.EKEntityTypeEvent,
                    lambda granted, error: None
                )

            return {
                "success": False,
                "error": "permission_needed",
                "message": "Calendar permission needed. Please go to System Settings → Privacy & Security → Calendars and enable access for Python/Terminal, then refresh.",
                "events": []
            }
        elif status == EventKit.EKAuthorizationStatusDenied or status == EventKit.EKAuthorizationStatusRestricted:
            return {
                "success": False,
                "error": "no_permission",
                "message": "Calendar access denied. Please grant permission in System Settings → Privacy & Security → Calendars → Enable for Terminal/Python.",
                "events": []
            }

        start_date = EventKit.NSDate.date()
        end_date = EventKit.NSDate.dateWithTimeIntervalSinceNow_(days_ahead * 24 * 60 * 60)

        calendars = store.calendarsForEntityType_(EventKit.EKEntityTypeEvent)

        if not calendars or len(calendars) == 0:
            return {
                "success": False,
                "error": "no_calendars",
                "message": "No calendars found. Make sure you have calendars set up in the Calendar app.",
                "events": []
            }

        predicate = store.predicateForEventsWithStartDate_endDate_calendars_(
            start_date, end_date, calendars
        )

        ek_events = store.eventsMatchingPredicate_(predicate)

        events = []
        for ek_event in ek_events:
            try:

                start = ek_event.startDate()
                if start:

                    timestamp = start.timeIntervalSince1970()
                    dt = datetime.fromtimestamp(timestamp)
                    date_str = dt.strftime("%Y-%m-%d")
                    time_str = dt.strftime("%H:%M") if not ek_event.allDay() else ""
                else:
                    date_str = datetime.now().strftime("%Y-%m-%d")
                    time_str = ""

                event = {
                    "id": str(ek_event.eventIdentifier() or hash(ek_event.title() or "")),
                    "title": str(ek_event.title() or "Untitled"),
                    "date": date_str,
                    "time": time_str,
                    "location": str(ek_event.location() or ""),
                    "description": str(ek_event.notes() or ""),
                    "source": "macos",
                    "calendar": str(ek_event.calendar().title()) if ek_event.calendar() else ""
                }
                events.append(event)
            except Exception:

                continue

        events.sort(key=lambda e: (e.get('date', ''), e.get('time', '')))

        return {
            "success": True,
            "events": events,
            "source": "macos"
        }

    except Exception as e:
        logging.error(f"EventKit error: {e}")
        return {
            "success": False,
            "error": "eventkit_error",
            "message": "Calendar error",
            "events": []
        }

def get_macos_calendar_events_icalbuddy(days_ahead: int = 14) -> Dict:

    try:
        cmd = [
            'icalBuddy',
            '-f',
            '-ea',
            '-b', '',
            '-nc',
            '-nrd',
            '-df', '%Y-%m-%d',
            '-tf', '%H:%M',
            '-iep', 'title,datetime,location,notes,uid',
            '-ps', '|:|',
            '-po', 'datetime,title,location,notes,uid',
            f'eventsToday+{days_ahead}'
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        if result.returncode != 0:
            if "No calendars" in result.stderr:
                return {
                    "success": False,
                    "error": "no_calendars",
                    "message": "icalBuddy cannot access calendars. Please grant Calendar access in System Settings > Privacy & Security > Calendars.",
                    "events": []
                }
            return {
                "success": False,
                "error": "command_failed",
                "message": result.stderr or "Failed to fetch calendar events",
                "events": []
            }

        events = parse_icalbuddy_output(result.stdout)
        return {
            "success": True,
            "events": events,
            "source": "macos"
        }

    except FileNotFoundError:
        return {
            "success": False,
            "error": "not_installed",
            "message": "icalBuddy not installed. Run: brew install ical-buddy",
            "events": []
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "error": "timeout",
            "message": "Calendar request timed out",
            "events": []
        }
    except Exception as e:
        logging.error(f"icalBuddy error: {e}")
        return {
            "success": False,
            "error": "unknown",
            "message": "Calendar error",
            "events": []
        }

def get_macos_calendar_events(days_ahead: int = 14) -> Dict:

    if EVENTKIT_AVAILABLE:
        result = get_macos_calendar_events_eventkit(days_ahead)
        if result["success"] or result.get("error") in ["no_permission", "no_calendars"]:
            return result

    return get_macos_calendar_events_icalbuddy(days_ahead)

def parse_icalbuddy_output(output: str) -> List[Dict]:

    events = []

    if not output.strip():
        return events

    lines = output.strip().split('\n')

    for line in lines:
        if not line.strip():
            continue

        parts = line.split('|:|')

        if len(parts) >= 2:
            datetime_str = parts[0].strip()
            title = parts[1].strip() if len(parts) > 1 else "Untitled"
            location = parts[2].strip() if len(parts) > 2 else ""
            notes = parts[3].strip() if len(parts) > 3 else ""
            uid = parts[4].strip() if len(parts) > 4 else str(hash(line))

            date_match = re.search(r'(\d{4}-\d{2}-\d{2})', datetime_str)
            time_match = re.search(r'(\d{2}:\d{2})', datetime_str)

            event = {
                "id": uid,
                "title": title,
                "date": date_match.group(1) if date_match else datetime.now().strftime("%Y-%m-%d"),
                "time": time_match.group(1) if time_match else "",
                "location": location,
                "description": notes,
                "source": "macos"
            }
            events.append(event)

    return events

def get_calendars() -> Dict:

    if EVENTKIT_AVAILABLE:
        try:
            store = EventKit.EKEventStore.alloc().init()
            calendars = store.calendarsForEntityType_(EventKit.EKEntityTypeEvent)

            cal_list = []
            for cal in calendars:
                cal_list.append({
                    "name": str(cal.title()),
                    "type": str(cal.type()),
                    "color": str(cal.color()) if cal.color() else None
                })

            return {"success": True, "calendars": cal_list}
        except Exception:
            pass

    try:
        result = subprocess.run(['icalBuddy', 'calendars'], capture_output=True, text=True, timeout=5)

        if result.returncode != 0:
            return {"success": False, "calendars": [], "error": result.stderr}

        calendars = []
        for line in result.stdout.strip().split('\n'):
            line = line.strip()
            if line and not line.startswith('•'):
                parts = line.split(' (')
                name = parts[0].strip()
                cal_type = parts[1].rstrip(')') if len(parts) > 1 else "local"
                calendars.append({"name": name, "type": cal_type})

        return {"success": True, "calendars": calendars}

    except Exception as e:
        logging.error(f"Calendar list error: {e}")
        return {"success": False, "calendars": [], "error": "Calendar error"}

def merge_events(macos_events: List[Dict], local_events: List[Dict]) -> List[Dict]:

    all_events = []
    seen_ids = set()

    for event in macos_events:
        event_id = event.get('id', '')
        if event_id not in seen_ids:
            seen_ids.add(event_id)
            all_events.append(event)

    for event in local_events:
        event_id = event.get('id', '')
        if event_id not in seen_ids:
            event['source'] = 'app'
            seen_ids.add(event_id)
            all_events.append(event)

    all_events.sort(key=lambda e: (e.get('date', ''), e.get('time', '')))

    return all_events
