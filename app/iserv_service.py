# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import logging
import socket
from datetime import datetime, timedelta
from pathlib import Path

from .crypto_utils import encrypt_file, decrypt_file

class IServWarningFilter(logging.Filter):
    def filter(self, record):

        if 'No data in publiccontact' in record.getMessage():
            return False
        return True

root_logger = logging.getLogger()
root_logger.addFilter(IServWarningFilter())

from urllib.parse import urlparse

from IServAPI import IServAPI
from .paths import DATA_DIR

CREDENTIALS_FILE = DATA_DIR / 'iserv_credentials.json'

_METADATA_IPS = {'169.254.169.254', 'fd00:ec2::254'}


def _check_blocked_ip(addr) -> str:
    mapped = getattr(addr, 'ipv4_mapped', None)
    if mapped is not None:
        addr = mapped
    if addr.is_loopback or addr.is_unspecified:
        return "Connection to loopback address is not allowed"
    if str(addr) in _METADATA_IPS:
        return "Connection to cloud metadata endpoint is not allowed"
    return None


_MAX_ATTACHMENT_BYTES = 12 * 1024 * 1024


def _same_host_only(urls, base_url: str):
    """Keep only URLs whose host is the IServ host itself."""
    base_host = (urlparse(base_url).hostname or '').lower()
    kept = []
    for url in urls:
        host = (urlparse(url).hostname or '').lower()
        if not host or host == base_host:
            kept.append(url)
        else:
            logging.debug('Vertretungsplan: dropped foreign URL host %s', host)
    return kept


def _read_capped(response, limit: int):
    """Read at most `limit` bytes from a streamed response, else give up."""
    chunks = []
    total = 0
    for chunk in response.iter_content(65536):
        total += len(chunk)
        if total > limit:
            return None
        chunks.append(chunk)
    return b''.join(chunks)


def _validate_hostname_ssrf(hostname: str) -> str:
    """Validate a hostname to prevent SSRF. Returns error message or None if valid.

    Blocks loopback, unspecified (0.0.0.0), and cloud metadata endpoints.
    Allows RFC 1918 / link-local so self-hosted LAN servers (e.g. an IServ
    reached via split-horizon DNS returning 10.x.x.x) remain reachable.
    """
    import ipaddress as _ipaddress
    if not hostname:
        return "Invalid hostname"
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

class IServService:

    def __init__(self):
        self.api = None
        self.connected = False
        self.user_info = None
        self.iserv_url = None
        self._try_auto_connect()

    def _try_auto_connect(self):
        creds = self.load_credentials()
        if creds:
            try:
                result = self.connect(
                    username=creds.get('username'),
                    password=creds.get('password'),
                    iserv_url=creds.get('iserv_url')
                )
                if result.get('success'):
                    logging.info('IServ auto-connected from saved credentials')
            except Exception as e:
                logging.debug(f'IServ auto-connect failed: {e}')

    def load_credentials(self):

        try:
            return decrypt_file(CREDENTIALS_FILE)
        except Exception:
            return None

    def save_credentials(self, username: str, password: str, iserv_url: str):

        encrypt_file({
            'username': username,
            'password': password,
            'iserv_url': iserv_url
        }, CREDENTIALS_FILE)

    def delete_credentials(self):

        if CREDENTIALS_FILE.exists():
            CREDENTIALS_FILE.unlink()
        self.disconnect()

    def connect(self, username: str = None, password: str = None, iserv_url: str = None):

        if not all([username, password, iserv_url]):
            creds = self.load_credentials()
            if creds:
                username = creds.get('username')
                password = creds.get('password')
                iserv_url = creds.get('iserv_url')

        if not all([username, password, iserv_url]):
            return {'success': False, 'error': 'Keine Anmeldedaten vorhanden'}

        try:
            iserv_url = iserv_url.replace('https://', '').replace('http://', '').strip('/')

            parsed = urlparse(f'https://{iserv_url}')
            if parsed.username or parsed.password or not parsed.hostname:
                return {'success': False, 'error': 'Ungültige IServ-Adresse'}

            ssrf_error = _validate_hostname_ssrf(parsed.hostname)
            if ssrf_error:
                return {'success': False, 'error': ssrf_error}

            self.api = IServAPI(
                username=username,
                password=password,
                iserv_url=iserv_url
            )

            self.iserv_url = iserv_url

            try:
                self.user_info = self.api.get_own_user_info()
            except Exception:
                self.user_info = {'name': username}

            self.connected = True

            self.save_credentials(username, password, iserv_url)

            return {
                'success': True,
                'user': {
                    'name': self.user_info.get('name', username) if isinstance(self.user_info, dict) else username,
                    'email': self.user_info.get('email', '') if isinstance(self.user_info, dict) else '',
                    'class': self.user_info.get('class', '') if isinstance(self.user_info, dict) else ''
                }
            }
        except ConnectionError as e:
            self.connected = False
            logging.error(f"IServ connection error: {e}")
            return {'success': False, 'error': 'Server nicht erreichbar. Bitte URL überprüfen.'}
        except Exception as e:
            self.connected = False
            error_str = str(e).lower()
            logging.error(f"IServ error: {e}")
            if 'authentication' in error_str or 'login' in error_str or 'password' in error_str or '401' in error_str or 'unauthorized' in error_str:
                return {'success': False, 'error': 'Falscher Benutzername oder Passwort'}
            elif 'timeout' in error_str or 'timed out' in error_str:
                return {'success': False, 'error': 'Zeitüberschreitung. Server antwortet nicht.'}
            elif 'connection' in error_str or 'network' in error_str or 'resolve' in error_str:
                return {'success': False, 'error': 'Server nicht erreichbar. Bitte URL überprüfen.'}
            elif 'ssl' in error_str or 'certificate' in error_str:
                return {'success': False, 'error': 'SSL-Zertifikatfehler'}
            else:
                return {'success': False, 'error': 'IServ-Verbindung fehlgeschlagen'}

    def disconnect(self):

        self.api = None
        self.connected = False
        self.user_info = None
        self.iserv_url = None

    def is_connected(self):

        return self.connected and self.api is not None

    def get_status(self):

        creds = self.load_credentials()
        return {
            'connected': self.connected,
            'has_credentials': creds is not None,
            'iserv_url': creds.get('iserv_url') if creds else None,
            'username': creds.get('username') if creds else None,
            'user_info': self.user_info
        }

    def get_notifications(self):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            notifications = self.api.get_notifications()
            return {'success': True, 'notifications': notifications}
        except Exception as e:
            logging.error(f"IServ notifications error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der Benachrichtigungen'}

    def get_badges(self):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            badges = self.api.get_badges()
            return {'success': True, 'badges': badges}
        except Exception as e:
            logging.error(f"IServ badges error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der Badges'}

    def mark_notification_read(self, notification_id: str):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            self.api.read_notification(notification_id)
            return {'success': True}
        except Exception as e:
            logging.error(f"IServ mark notification error: {e}")
            return {'success': False, 'error': 'Fehler beim Aktualisieren der Benachrichtigung'}

    def get_emails(self, folder: str = 'INBOX', limit: int = 20):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            emails = self.api.get_emails(path=folder, length=limit)
            return {'success': True, 'emails': emails}
        except Exception as e:
            logging.error(f"IServ emails error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der E-Mails'}

    def get_mail_folders(self):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            folders = self.api.get_mail_folders()
            return {'success': True, 'folders': folders}
        except Exception as e:
            logging.error(f"IServ mail folders error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der Ordner'}

    def get_email_detail(self, msg_id: str, folder: str = 'INBOX'):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:

            email = self.api.get_mail(uid=msg_id, path=folder)
            if email:
                return {
                    'success': True,
                    'email': {
                        'id': msg_id,
                        'from': email.get('from', email.get('sender', '')),
                        'from_name': email.get('from_name', email.get('from', '').split('@')[0] if email.get('from') else ''),
                        'to': email.get('to', ''),
                        'subject': email.get('subject', '(Kein Betreff)'),
                        'date': email.get('date', ''),
                        'body': email.get('body', email.get('html', email.get('text', ''))),
                        'html': email.get('html', ''),
                        'attachments': email.get('attachments', [])
                    }
                }
            return {'success': False, 'error': 'E-Mail nicht gefunden'}
        except Exception as e:
            logging.error(f"IServ email detail error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der E-Mail'}

    def send_email(self, to: str, subject: str, body: str, attachments: list = None):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:

            self.api.send_email(
                to=to,
                subject=subject,
                text=body
            )
            return {'success': True}
        except Exception as e:
            logging.error(f"IServ send email error: {e}")
            return {'success': False, 'error': 'Fehler beim Senden der E-Mail'}

    def get_upcoming_events(self, days: int = 60):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        all_events = []
        errors = []

        start = datetime.now()
        end = start + timedelta(days=days)

        start_str = start.strftime('%Y-%m-%d')
        end_str = end.strftime('%Y-%m-%d')

        try:
            events = self.api.get_events(start=start_str, end=end_str)
            if events:
                if isinstance(events, list):
                    all_events.extend(events)
                else:
                    all_events.append(events)
                logging.info(f"IServ get_events returned {len(events) if isinstance(events, list) else 1} events")
        except Exception as e:
            logging.error(f"IServ get_events error: {e}")
            errors.append("get_events: Abruf fehlgeschlagen")

        try:
            events = self.api.get_upcoming_events()
            if events:
                if isinstance(events, list):
                    all_events.extend(events)
                else:
                    all_events.append(events)
                logging.info(f"IServ get_upcoming_events returned {len(events) if isinstance(events, list) else 1} events")
        except Exception as e:
            logging.error(f"IServ get_upcoming_events error: {e}")
            errors.append("get_upcoming_events: Abruf fehlgeschlagen")

        try:
            if hasattr(self.api, 'get_calendar'):
                calendar = self.api.get_calendar()
                if calendar:
                    if isinstance(calendar, list):
                        all_events.extend(calendar)
                    else:
                        all_events.append(calendar)
        except Exception as e:
            logging.error(f"IServ get_calendar error: {e}")
            errors.append("get_calendar: Abruf fehlgeschlagen")

        seen = set()
        unique_events = []
        for event in all_events:
            if not isinstance(event, dict):
                continue
            event_id = event.get('id') or event.get('uid') or str(hash(str(event)))
            if event_id not in seen:
                seen.add(event_id)

                normalized = self._normalize_event(event)
                unique_events.append(normalized)

        if unique_events:
            return {'success': True, 'events': unique_events}
        elif errors:
            return {'success': False, 'error': 'Keine Events gefunden', 'details': errors, 'events': []}
        else:
            return {'success': True, 'events': []}

    def _normalize_event(self, event):

        date_val = (event.get('date') or event.get('start') or
                   event.get('dtstart') or event.get('start_date') or
                   event.get('begin') or event.get('startDate'))

        if hasattr(date_val, 'isoformat'):
            date_val = date_val.isoformat()
        elif isinstance(date_val, str) and len(date_val) >= 10:

            pass
        else:
            date_val = None

        return {
            'id': event.get('id') or event.get('uid') or event.get('eventId'),
            'title': event.get('title') or event.get('summary') or event.get('name') or event.get('subject') or 'Termin',
            'date': date_val,
            'start': date_val,
            'end': event.get('end') or event.get('dtend') or event.get('end_date') or event.get('endDate'),
            'description': event.get('description') or event.get('notes') or event.get('body') or '',
            'location': event.get('location') or event.get('place') or event.get('room') or '',
            'calendar': event.get('calendar') or event.get('calendarName') or event.get('category') or 'IServ',
            'all_day': event.get('allDay') or event.get('all_day') or event.get('allday') or False,
            'source': 'iserv'
        }

    def get_events_in_range(self, start_date: datetime, end_date: datetime):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:

            start_str = start_date.strftime('%Y-%m-%d')
            end_str = end_date.strftime('%Y-%m-%d')

            events = self.api.get_events(start=start_str, end=end_str)
            return {'success': True, 'events': events if events else []}
        except Exception as e:
            logging.error(f"IServ events in range error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der Termine'}

    def create_event(self, title: str, start: datetime, end: datetime = None,
                     description: str = '', location: str = ''):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            self.api.create_event(
                title=title,
                start=start,
                end=end or start + timedelta(hours=1),
                description=description,
                location=location
            )
            return {'success': True}
        except Exception as e:
            logging.error(f"IServ create event error: {e}")
            return {'success': False, 'error': 'Fehler beim Erstellen des Termins'}

    def get_exercises(self):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        exercises = []

        try:

            start = datetime.now()
            end = start + timedelta(days=60)
            start_str = start.strftime('%Y-%m-%d')
            end_str = end.strftime('%Y-%m-%d')

            all_events = []
            try:
                events = self.api.get_events(start=start_str, end=end_str)
                if events:
                    all_events.extend(events if isinstance(events, list) else [events])
            except Exception as e:
                print(f"get_events failed: {e}")

            try:
                upcoming = self.api.get_upcoming_events()
                if upcoming:
                    all_events.extend(upcoming if isinstance(upcoming, list) else [upcoming])
            except Exception as e:
                print(f"get_upcoming_events failed: {e}")

            try:
                if hasattr(self.api, 'get_calendar_plugin_events'):
                    plugin_events = self.api.get_calendar_plugin_events()
                    if plugin_events:
                        all_events.extend(plugin_events if isinstance(plugin_events, list) else [plugin_events])
            except Exception as e:
                print(f"get_calendar_plugin_events failed: {e}")

            exercise_keywords = [
                'aufgabe', 'exercise', 'hausaufgabe', 'abgabe', 'task', 'homework',
                'ha:', 'ha ', 'klausur', 'test', 'arbeit', 'vokabel', 'lesen',
                'bearbeiten', 'lernen', 'üben', 'wiederholen', 'vorbereiten'
            ]
            for event in all_events:
                if not isinstance(event, dict):
                    continue
                title = (event.get('title') or event.get('summary') or event.get('name') or '').lower()
                desc = (event.get('description') or event.get('notes') or '').lower()
                is_exercise = any(kw in title or kw in desc for kw in exercise_keywords)

                calendar = (event.get('calendar') or event.get('calendarName') or '').lower()
                if 'aufgabe' in calendar or 'exercise' in calendar or 'homework' in calendar:
                    is_exercise = True

                if is_exercise:
                    exercises.append({
                        'id': event.get('id') or event.get('uid') or str(hash(title)),
                        'title': event.get('title') or event.get('summary') or event.get('name') or 'Aufgabe',
                        'due': event.get('start') or event.get('dtstart') or event.get('end'),
                        'description': event.get('description') or event.get('notes') or '',
                        'course': event.get('calendar') or event.get('calendarName'),
                        'source': 'calendar_event'
                    })

        except Exception as e:
            print(f"calendar exercise filter failed: {e}")

        seen = set()
        unique_exercises = []
        for ex in exercises:
            title = (ex.get('title') or '').lower().strip()
            due = ex.get('due') or ''
            key = f"{title}|{due[:10] if due else ''}"
            if key not in seen:
                seen.add(key)
                unique_exercises.append(ex)

        unique_exercises.sort(key=lambda x: x.get('due') or '9999-99-99')

        return {'success': True, 'exercises': unique_exercises}

    def _normalize_exercises(self, raw_data):

        normalized = []
        if not raw_data:
            return normalized

        items = raw_data if isinstance(raw_data, list) else [raw_data]

        for item in items:
            if not isinstance(item, dict):
                continue

            normalized.append({
                'id': item.get('id') or item.get('uid') or item.get('exercise_id'),
                'title': item.get('title') or item.get('name') or item.get('subject') or 'Aufgabe',
                'description': item.get('description') or item.get('text') or item.get('body') or '',
                'due': item.get('due') or item.get('due_date') or item.get('deadline') or item.get('end'),
                'created': item.get('created') or item.get('created_at') or item.get('start'),
                'course': item.get('course') or item.get('class') or item.get('fach'),
                'teacher': item.get('teacher') or item.get('author') or item.get('created_by'),
                'status': item.get('status') or ('done' if item.get('completed') else 'open'),
                'attachments': item.get('attachments') or item.get('files') or []
            })

        return normalized

    def get_storage_info(self):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            storage = self.api.get_disk_space()
            return {'success': True, 'storage': storage}
        except Exception as e:
            logging.error(f"IServ storage error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der Speicherinformationen'}

    def list_files(self, path: str = '/'):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:

            webdav_client = self.api.file(path=path)

            files = webdav_client.list(path)
            return {'success': True, 'files': files, 'path': path}
        except Exception as e:
            logging.error(f"IServ list files error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der Dateien'}

    def get_file_info(self, path: str):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            webdav_client = self.api.file()
            info = webdav_client.info(path)
            return {'success': True, 'info': info}
        except Exception as e:
            logging.error(f"IServ file info error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen der Dateiinformationen'}

    def download_file(self, remote_path: str, local_path: str):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            webdav_client = self.api.file()
            webdav_client.download(remote_path, local_path)
            return {'success': True, 'local_path': local_path}
        except Exception as e:
            logging.error(f"IServ download file error: {e}")
            return {'success': False, 'error': 'Fehler beim Herunterladen der Datei'}

    def search_users(self, query: str):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:
            users = self.api.search_users(query)
            return {'success': True, 'users': users}
        except Exception as e:
            logging.error(f"IServ search users error: {e}")
            return {'success': False, 'error': 'Fehler bei der Benutzersuche'}

    VERTRETUNGSPLAN_CACHE_DIR = DATA_DIR / 'vertretungsplan_cache'

    def get_vertretungsplan_pdfs(self, display_id: int = 3):
        cache_dir = self.VERTRETUNGSPLAN_CACHE_DIR
        cache_dir.mkdir(parents=True, exist_ok=True)
        cache_meta_file = cache_dir / 'cache_meta.json'

        if not self.is_connected():
            creds = self.load_credentials()
            if creds:
                logging.info("Auto-connecting to IServ for Vertretungsplan...")
                self.connect()

        if self.is_connected():
            try:
                result = self._fetch_vertretungsplan_pdfs(display_id)
                if result.get('success') and result.get('pdfs'):

                    self._cache_vertretungsplan_pdfs(result['pdfs'], cache_dir, cache_meta_file)
                    return result
                elif not result.get('success'):

                    cached = self._get_cached_vertretungsplan(cache_dir, cache_meta_file)
                    if cached.get('success'):
                        cached['fetch_error'] = result.get('error')
                        return cached

                    result['iserv_connected'] = True
                    return result
            except Exception as e:
                logging.error(f"Error fetching Vertretungsplan: {e}")

        cached = self._get_cached_vertretungsplan(cache_dir, cache_meta_file)
        if not cached.get('success'):

            creds = self.load_credentials()
            if not creds:
                cached['error'] = 'IServ nicht konfiguriert. Gehe zu Einstellungen um dich anzumelden.'
                cached['needs_setup'] = True
            else:
                cached['error'] = 'IServ-Verbindung fehlgeschlagen. Bitte melde dich erneut an.'
                cached['needs_reconnect'] = True
        return cached

    def _fetch_vertretungsplan_pdfs(self, display_id: int = 3):

        import base64
        import re
        from concurrent.futures import ThreadPoolExecutor, as_completed

        base_url = self.iserv_url.rstrip('/')
        if not base_url.startswith('http'):
            base_url = f'https://{base_url}'

        session = self.api._session if hasattr(self.api, '_session') else None
        if session is None:
            return {'success': False, 'error': 'Keine Sitzung verfügbar'}

        infodisplay_url = f'{base_url}/iserv/infodisplay/show/{display_id}'
        response = session.get(infodisplay_url, timeout=10)

        if response.status_code != 200:
            return {'success': False, 'error': f'HTTP {response.status_code}'}

        content_type = response.headers.get('Content-Type', '')

        if 'application/pdf' in content_type:
            pdf_base64 = base64.b64encode(response.content).decode('utf-8')
            return {
                'success': True,
                'pdfs': [{
                    'data': pdf_base64,
                    'filename': 'vertretungsplan.pdf',
                    'page': 1
                }],
                'fetched_at': datetime.now().isoformat()
            }

        if 'text/html' in content_type:
            from bs4 import BeautifulSoup
            soup = BeautifulSoup(response.text, 'html.parser')

            pdfs = []

            pdf_links = []
            for link in soup.find_all('a', href=True):
                href = link['href']
                if '.pdf' in href.lower():
                    if not href.startswith('http'):
                        href = f'{base_url}{href}' if href.startswith('/') else f'{base_url}/{href}'
                    pdf_links.append(href)

            for obj in soup.find_all(['object', 'embed']):
                data = obj.get('data') or obj.get('src')
                if data and '.pdf' in data.lower():
                    if not data.startswith('http'):
                        data = f'{base_url}{data}' if data.startswith('/') else f'{base_url}/{data}'
                    pdf_links.append(data)

            for iframe in soup.find_all('iframe'):
                src = iframe.get('src', '')
                if '.pdf' in src.lower() or 'infodisplay' in src.lower():
                    if not src.startswith('http'):
                        src = f'{base_url}{src}' if src.startswith('/') else f'{base_url}/{src}'
                    pdf_links.append(src)

            scripts = soup.find_all('script')
            for script in scripts:
                if script.string:

                    pdf_matches = re.findall(r'["\']([^"\']*\.pdf[^"\']*)["\']', script.string, re.IGNORECASE)
                    for match in pdf_matches:
                        if not match.startswith('http'):
                            match = f'{base_url}{match}' if match.startswith('/') else f'{base_url}/{match}'
                        pdf_links.append(match)

            priority_urls = [
                f'{base_url}/iserv/infodisplay/file/{display_id}/{i}'
                for i in range(1, 7)
            ]

            def check_url_fast(url):
                try:
                    resp = session.head(url, timeout=3, allow_redirects=True)
                    if resp.status_code == 200:
                        ct = resp.headers.get('Content-Type', '')
                        if 'html' not in ct.lower():
                            return url
                except Exception:
                    pass
                return None

            with ThreadPoolExecutor(max_workers=4) as executor:
                futures = {executor.submit(check_url_fast, url): url for url in priority_urls}
                for future in as_completed(futures, timeout=5):
                    try:
                        result = future.result()
                        if result:
                            pdf_links.insert(0, result)
                    except Exception:
                        pass

            for img in soup.find_all('img'):
                src = img.get('src', '')

                if src and ('vertretung' in src.lower() or 'plan' in src.lower() or
                           'infodisplay' in src.lower() or '/file/' in src.lower() or
                           'upload' in src.lower()):
                    if not src.startswith('http'):
                        src = f'{base_url}{src}' if src.startswith('/') else f'{base_url}/{src}'
                    pdf_links.append(src)

            for elem in soup.find_all(attrs={'data-src': True}):
                src = elem.get('data-src', '')
                if src:
                    if not src.startswith('http'):
                        src = f'{base_url}{src}' if src.startswith('/') else f'{base_url}/{src}'
                    pdf_links.append(src)

            for elem in soup.find_all(style=True):
                style = elem.get('style', '')
                bg_matches = re.findall(r'url\(["\']?([^"\')\s]+)["\']?\)', style)
                for match in bg_matches:
                    if not match.startswith('http'):
                        match = f'{base_url}{match}' if match.startswith('/') else f'{base_url}/{match}'
                    pdf_links.append(match)

            file_links = re.findall(r'(/iserv/file/[^"\'>\s]+)', response.text)
            for file_link in file_links:
                full_url = f'{base_url}{file_link}'
                if full_url not in pdf_links:
                    pdf_links.append(full_url)

            for script in scripts:
                if script.string:

                    url_matches = re.findall(r'["\'](/iserv/[^"\']+)["\']', script.string)
                    for match in url_matches:
                        if 'file' in match.lower() or 'image' in match.lower() or 'display' in match.lower():
                            pdf_links.append(f'{base_url}{match}')

                    img_matches = re.findall(r'["\']([^"\']*\.(png|jpg|jpeg|gif)[^"\']*)["\']', script.string, re.IGNORECASE)
                    for match, _ext in img_matches:
                        if not match.startswith('http'):
                            match = f'{base_url}{match}' if match.startswith('/') else f'{base_url}/{match}'
                        pdf_links.append(match)

            seen = set()
            unique_links = []
            for link in pdf_links:
                if link not in seen:
                    seen.add(link)
                    unique_links.append(link)

            unique_links = [url for url in unique_links if not url.startswith('data:')]
            unique_links = _same_host_only(unique_links, base_url)

            logging.info(f"Vertretungsplan: {len(unique_links)} URLs to check")

            def fetch_pdf(url):
                try:
                    with session.get(url, timeout=8, stream=True) as resp:
                        if resp.status_code != 200:
                            return None
                        if not _same_host_only([resp.url], base_url):
                            logging.debug('Vertretungsplan: redirect left the IServ host')
                            return None
                        ct = resp.headers.get('Content-Type', '').lower()

                        if 'text/html' in ct or 'svg' in ct:
                            return None
                        if not ('pdf' in ct or 'image' in ct):
                            return None

                        content = _read_capped(resp, _MAX_ATTACHMENT_BYTES)
                        if content is None or len(content) < 10000:
                            return None
                        return {'url': url, 'content': content, 'content_type': ct}
                except Exception:
                    return None

            with ThreadPoolExecutor(max_workers=6) as executor:

                futures = {executor.submit(fetch_pdf, url): url for url in unique_links[:10]}
                for future in as_completed(futures, timeout=15):
                    if len(pdfs) >= 6:
                        break
                    try:
                        result = future.result()
                        if result:
                            pdf_content_type = result['content_type']
                            pdf_base64 = base64.b64encode(result['content']).decode('utf-8')
                            page_num = len(pdfs) + 1

                            if 'pdf' in pdf_content_type:
                                file_type = 'pdf'
                                filename = f'vertretungsplan_tag{page_num}.pdf'
                            else:
                                file_type = 'image'
                                ext = 'png' if 'png' in pdf_content_type else 'jpg'
                                filename = f'vertretungsplan_tag{page_num}.{ext}'

                            pdfs.append({
                                'data': pdf_base64,
                                'filename': filename,
                                'page': page_num,
                                'content_type': pdf_content_type,
                                'type': file_type,
                                'url': result['url']
                            })
                            logging.info(f"Vertretungsplan: Fetched {file_type} from {result['url']}")
                    except Exception:
                        pass

            if pdfs:
                return {
                    'success': True,
                    'pdfs': pdfs,
                    'fetched_at': datetime.now().isoformat()
                }

            all_media = []
            for tag in soup.find_all(['img', 'iframe', 'object', 'embed']):
                src = tag.get('src') or tag.get('data') or tag.get('data-src')
                if src:
                    all_media.append(f"{tag.name}: {src}")

            return {
                'success': False,
                'error': 'Keine PDFs gefunden',
                'media_elements': all_media[:20],
                'page_title': soup.title.string if soup.title else 'No title'
            }

        return {'success': False, 'error': f'Unbekannter Content-Type: {content_type}'}

    def _cache_vertretungsplan_pdfs(self, pdfs: list, cache_dir: Path, meta_file: Path):

        import base64

        try:
            for pdf in pdfs:
                import re as _re
                raw_name = pdf.get('filename', f'page_{pdf.get("page", 1)}.pdf')
                filename = _re.sub(r'[^a-zA-Z0-9._-]', '_', raw_name)[:100]
                if not filename.endswith('.pdf'):
                    filename += '.pdf'
                file_path = cache_dir / filename
                if not file_path.resolve().parent == cache_dir.resolve():
                    continue

                pdf_data = base64.b64decode(pdf['data'])
                with open(file_path, 'wb') as f:
                    f.write(pdf_data)

            meta = {
                'cached_at': datetime.now().isoformat(),
                'files': [
                    {
                        'filename': pdf.get('filename'),
                        'page': pdf.get('page'),
                        'content_type': pdf.get('content_type'),
                        'type': pdf.get('type', 'pdf')
                    }
                    for pdf in pdfs
                ]
            }
            encrypt_file(meta, meta_file)

            logging.info(f"Cached {len(pdfs)} Vertretungsplan files")
        except Exception as e:
            logging.error(f"Error caching Vertretungsplan: {e}")

    def _get_cached_vertretungsplan(self, cache_dir: Path, meta_file: Path):

        import base64

        if not meta_file.exists():
            return {
                'success': False,
                'error': 'Kein Cache vorhanden',
                'offline': True
            }

        try:
            meta = decrypt_file(meta_file)

            pdfs = []
            for file_info in meta.get('files', []):
                file_path = cache_dir / file_info['filename']
                if not file_path.resolve().parent == cache_dir.resolve():
                    continue
                if file_path.exists():
                    with open(file_path, 'rb') as f:
                        pdf_data = f.read()

                    pdfs.append({
                        'data': base64.b64encode(pdf_data).decode('utf-8'),
                        'filename': file_info['filename'],
                        'page': file_info['page'],
                        'content_type': file_info.get('content_type', 'application/pdf'),
                        'type': file_info.get('type', 'pdf')
                    })

            if pdfs:
                return {
                    'success': True,
                    'pdfs': pdfs,
                    'cached_at': meta.get('cached_at'),
                    'from_cache': True
                }

            return {
                'success': False,
                'error': 'Cache-Dateien nicht gefunden',
                'offline': True
            }

        except Exception as e:
            logging.error(f"IServ Vertretungsplan cache error: {e}")
            return {
                'success': False,
                'error': 'Cache-Fehler',
                'offline': True
            }

    def get_vertretungsplan(self, display_id: int = 3):

        return self.get_vertretungsplan_pdfs(display_id)

    def get_vertretungsplan_image(self, display_id: int = 3):

        if not self.is_connected():
            return {'success': False, 'error': 'Nicht verbunden'}

        try:

            base_url = self.iserv_url.rstrip('/')
            if not base_url.startswith('http'):
                base_url = f'https://{base_url}'
            infodisplay_url = f'{base_url}/iserv/infodisplay/show/{display_id}'

            session = self.api._session if hasattr(self.api, '_session') else None
            if session is None:
                return {'success': False, 'error': 'Keine Sitzung verfügbar'}

            response = session.get(infodisplay_url, timeout=30)

            if response.status_code != 200:
                return {'success': False, 'error': f'HTTP {response.status_code}'}

            content_type = response.headers.get('Content-Type', '')
            if 'image' in content_type:
                return {
                    'success': True,
                    'image_data': response.content,
                    'content_type': content_type
                }
            else:
                return {'success': False, 'error': 'Kein Bild gefunden'}

        except Exception as e:
            logging.error(f"IServ Vertretungsplan image error: {e}")
            return {'success': False, 'error': 'Fehler beim Abrufen des Vertretungsplans'}

iserv_service = IServService()

def get_iserv_service():

    return iserv_service
