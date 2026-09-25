# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import os
import base64
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(PROJECT_ROOT, ".env"))

from .crypto_utils import encrypt_file, decrypt_file

try:
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import Flow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build
    GOOGLE_API_AVAILABLE = True
except ImportError:
    GOOGLE_API_AVAILABLE = False

DATA_DIR = os.environ.get("HUB_DATA_DIR") or os.path.join(PROJECT_ROOT, "data")
os.makedirs(DATA_DIR, exist_ok=True)
CREDENTIALS_FILE = Path(DATA_DIR) / "google_credentials.json"
TOKENS_FILE = Path(DATA_DIR) / "google_tokens.json"

GOOGLE_CLIENT_ID = os.getenv('GOOGLE_CLIENT_ID')
GOOGLE_CLIENT_SECRET = os.getenv('GOOGLE_CLIENT_SECRET')
GOOGLE_REDIRECT_URI = os.getenv('GOOGLE_REDIRECT_URI', 'http://localhost:5050/api/email/google/oauth-callback')

SCOPES = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/gmail.modify',
    'https://www.googleapis.com/auth/calendar'
]

def is_google_oauth_configured() -> bool:

    if GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET:
        return GOOGLE_API_AVAILABLE
    return GOOGLE_API_AVAILABLE and CREDENTIALS_FILE.exists()

def get_oauth_status() -> Dict:

    if not GOOGLE_API_AVAILABLE:
        return {
            "configured": False,
            "authenticated": False,
            "error": "Google API libraries not installed"
        }

    if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
        if not CREDENTIALS_FILE.exists():
            return {
                "configured": False,
                "authenticated": False,
                "message": "Google OAuth not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env file."
            }

    tokens = load_tokens()
    authenticated = bool(tokens)

    return {
        "configured": True,
        "authenticated": authenticated,
        "accounts": list(tokens.keys()) if tokens else []
    }

def load_tokens() -> Dict:

    try:
        data = decrypt_file(TOKENS_FILE)
        return data if data else {}
    except Exception:
        return {}

def save_tokens(tokens: Dict) -> bool:

    try:
        encrypt_file(tokens, TOKENS_FILE)
        return True
    except Exception:
        return False

def get_credentials(email: str) -> Optional[Credentials]:

    tokens = load_tokens()
    token_data = tokens.get(email)

    if not token_data:
        return None

    creds = Credentials(
        token=token_data.get('token'),
        refresh_token=token_data.get('refresh_token'),
        token_uri='https://oauth2.googleapis.com/token',
        client_id=GOOGLE_CLIENT_ID or token_data.get('client_id'),
        client_secret=GOOGLE_CLIENT_SECRET or token_data.get('client_secret'),
        scopes=SCOPES
    )

    if creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())

            tokens[email] = {
                'token': creds.token,
                'refresh_token': creds.refresh_token,
                'token_uri': creds.token_uri,
                'client_id': creds.client_id,
                'client_secret': creds.client_secret
            }
            save_tokens(tokens)
        except Exception as e:

            if 'invalid_grant' in str(e) or 'revoked' in str(e).lower():
                if email in tokens:
                    del tokens[email]
                    save_tokens(tokens)
            return None

    return creds

def _get_oauth_client_config() -> Dict:

    if GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET:
        return {
            "web": {
                "client_id": GOOGLE_CLIENT_ID,
                "client_secret": GOOGLE_CLIENT_SECRET,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
                "redirect_uris": [GOOGLE_REDIRECT_URI]
            }
        }

    creds_data = decrypt_file(CREDENTIALS_FILE)
    if creds_data:
        if "installed" in creds_data:
            installed = creds_data["installed"]
            return {
                "web": {
                    "client_id": installed["client_id"],
                    "client_secret": installed["client_secret"],
                    "auth_uri": installed.get("auth_uri", "https://accounts.google.com/o/oauth2/auth"),
                    "token_uri": installed.get("token_uri", "https://oauth2.googleapis.com/token"),
                    "redirect_uris": [GOOGLE_REDIRECT_URI]
                }
            }
        return creds_data

    return None

def start_oauth_flow() -> Dict:

    if not GOOGLE_API_AVAILABLE:
        return {"success": False, "error": "Google API not available"}

    client_config = _get_oauth_client_config()
    if not client_config:
        return {"success": False, "error": "Google credentials not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env file."}

    try:
        flow = Flow.from_client_config(
            client_config,
            scopes=SCOPES,
            redirect_uri=GOOGLE_REDIRECT_URI
        )

        auth_url, state = flow.authorization_url(
            access_type='offline',
            prompt='consent'
        )

        return {
            "success": True,
            "auth_url": auth_url,
            "state": state,
            "message": "Open this URL in your browser and authorize access"
        }
    except Exception as e:
        logging.error(f"Google OAuth flow error: {e}")
        return {"success": False, "error": "Failed to start Google sign-in"}

def complete_oauth_flow(auth_code: str) -> Dict:

    if not GOOGLE_API_AVAILABLE:
        return {"success": False, "error": "Google API not available"}

    client_config = _get_oauth_client_config()
    if not client_config:
        return {"success": False, "error": "Google credentials not configured"}

    try:
        flow = Flow.from_client_config(
            client_config,
            scopes=SCOPES,
            redirect_uri=GOOGLE_REDIRECT_URI
        )

        flow.fetch_token(code=auth_code, timeout=30)
        creds = flow.credentials

        service = build('gmail', 'v1', credentials=creds)
        profile = service.users().getProfile(userId='me').execute()
        email = profile.get('emailAddress', '')

        if not email:
            return {"success": False, "error": "Could not get email address"}

        tokens = load_tokens()
        tokens[email] = {
            'token': creds.token,
            'refresh_token': creds.refresh_token,
            'token_uri': creds.token_uri,
            'client_id': creds.client_id,
            'client_secret': creds.client_secret
        }
        save_tokens(tokens)

        return {
            "success": True,
            "email": email,
            "message": f"Successfully connected {email}"
        }

    except Exception as e:
        logging.error(f"Google OAuth completion error: {e}")
        return {"success": False, "error": "Failed to complete Google sign-in"}

def remove_google_account(email: str) -> bool:

    tokens = load_tokens()
    if email in tokens:
        del tokens[email]
        save_tokens(tokens)
        return True
    return False

def get_google_accounts() -> List[Dict]:

    tokens = load_tokens()
    return [{"email": email, "provider": "gmail_oauth"} for email in tokens.keys()]

def fetch_gmail_messages(email: str, max_results: int = 20) -> Dict:

    creds = get_credentials(email)
    if not creds:
        return {"success": False, "error": "Not authenticated. Please sign in again."}

    try:
        service = build('gmail', 'v1', credentials=creds)

        results = service.users().messages().list(
            userId='me',
            maxResults=max_results,
            labelIds=['INBOX']
        ).execute()

        messages = results.get('messages', [])
        emails = []

        for msg in messages:
            try:
                msg_data = service.users().messages().get(
                    userId='me',
                    id=msg['id'],
                    format='metadata',
                    metadataHeaders=['From', 'Subject', 'Date']
                ).execute()

                headers = {h['name']: h['value'] for h in msg_data.get('payload', {}).get('headers', [])}

                from_header = headers.get('From', '')
                from_name = from_header.split('<')[0].strip().strip('"') if '<' in from_header else from_header.split('@')[0]
                from_email = from_header.split('<')[1].rstrip('>') if '<' in from_header else from_header

                date_str = headers.get('Date', '')
                try:
                    from email.utils import parsedate_to_datetime
                    date_obj = parsedate_to_datetime(date_str)
                    date_formatted = date_obj.strftime("%Y-%m-%d %H:%M")
                except Exception:
                    date_formatted = date_str[:20]

                preview = msg_data.get('snippet', '')[:200]

                is_read = 'UNREAD' not in msg_data.get('labelIds', [])

                emails.append({
                    "id": msg['id'],
                    "from": from_email,
                    "from_name": from_name,
                    "subject": headers.get('Subject', '(No Subject)'),
                    "date": date_formatted,
                    "preview": preview,
                    "read": is_read
                })
            except Exception:
                continue

        return {"success": True, "emails": emails}

    except Exception as e:
        logging.error(f"Gmail fetch error: {e}")
        return {"success": False, "error": "Failed to fetch emails"}

def get_gmail_message_detail(email: str, msg_id: str) -> Dict:

    creds = get_credentials(email)
    if not creds:
        return {"success": False, "error": "Not authenticated"}

    try:
        service = build('gmail', 'v1', credentials=creds)

        msg_data = service.users().messages().get(
            userId='me',
            id=msg_id,
            format='full'
        ).execute()

        headers = {h['name']: h['value'] for h in msg_data.get('payload', {}).get('headers', [])}

        from_header = headers.get('From', '')
        from_name = from_header.split('<')[0].strip().strip('"') if '<' in from_header else from_header.split('@')[0]
        from_email = from_header.split('<')[1].rstrip('>') if '<' in from_header else from_header

        date_str = headers.get('Date', '')
        try:
            from email.utils import parsedate_to_datetime
            date_obj = parsedate_to_datetime(date_str)
            date_formatted = date_obj.strftime("%Y-%m-%d %H:%M")
        except Exception:
            date_formatted = date_str

        body = ""
        payload = msg_data.get('payload', {})

        def get_body_from_parts(parts):
            for part in parts:
                if part.get('mimeType') == 'text/plain':
                    data = part.get('body', {}).get('data', '')
                    if data:
                        return base64.urlsafe_b64decode(data).decode('utf-8', errors='replace')
                elif part.get('parts'):
                    result = get_body_from_parts(part['parts'])
                    if result:
                        return result
            return ""

        if payload.get('parts'):
            body = get_body_from_parts(payload['parts'])
        elif payload.get('body', {}).get('data'):
            body = base64.urlsafe_b64decode(payload['body']['data']).decode('utf-8', errors='replace')

        try:
            service.users().messages().modify(
                userId='me',
                id=msg_id,
                body={'removeLabelIds': ['UNREAD']}
            ).execute()
        except Exception:
            pass

        return {
            "success": True,
            "email": {
                "id": msg_id,
                "from": from_email,
                "from_name": from_name,
                "to": headers.get('To', ''),
                "subject": headers.get('Subject', '(No Subject)'),
                "date": date_formatted,
                "body": body
            }
        }

    except Exception as e:
        logging.error(f"Gmail message detail error: {e}")
        return {"success": False, "error": "Failed to fetch email details"}

def send_gmail(from_email: str, to_email: str, subject: str, body: str) -> Dict:

    creds = get_credentials(from_email)
    if not creds:
        return {"success": False, "error": "Not authenticated"}

    try:
        service = build('gmail', 'v1', credentials=creds)

        to_email = to_email.replace('\r', '').replace('\n', '')
        subject = subject.replace('\r', '').replace('\n', '')

        message = MIMEMultipart()
        message['To'] = to_email
        message['Subject'] = subject
        message.attach(MIMEText(body, 'plain', 'utf-8'))

        raw = base64.urlsafe_b64encode(message.as_bytes()).decode('utf-8')

        service.users().messages().send(
            userId='me',
            body={'raw': raw}
        ).execute()

        return {"success": True, "message": "Email sent successfully"}

    except Exception as e:
        logging.error(f"Gmail send error: {e}")
        return {"success": False, "error": "Failed to send email"}

def fetch_google_calendar_events(days_ahead: int = 30, account_email: str = None,
                                  start_date: str = None, end_date: str = None) -> Dict:
    tokens = load_tokens()

    if not tokens:
        return {
            "success": False,
            "error": "not_authenticated",
            "message": "No Google account connected. Add one in the Email section.",
            "events": []
        }

    if account_email and account_email in tokens:
        email = account_email
    else:
        email = list(tokens.keys())[0]

    creds = get_credentials(email)

    if not creds:
        return {
            "success": False,
            "error": "auth_expired",
            "message": "Google authentication expired. Please sign in again.",
            "events": []
        }

    try:
        service = build('calendar', 'v3', credentials=creds)

        if start_date and end_date:

            time_min = f"{start_date}T00:00:00Z"
            time_max = f"{end_date}T23:59:59Z"
        else:
            now = datetime.utcnow()
            time_min = now.isoformat() + 'Z'
            time_max = (now + timedelta(days=days_ahead)).isoformat() + 'Z'

        calendar_list = service.calendarList().list().execute()
        calendars = calendar_list.get('items', [])

        all_events = []

        for cal in calendars:
            cal_id = cal.get('id')
            cal_name = cal.get('summary', 'Calendar')
            cal_color = cal.get('backgroundColor', '#4285f4')

            try:
                events_result = service.events().list(
                    calendarId=cal_id,
                    timeMin=time_min,
                    timeMax=time_max,
                    maxResults=100,
                    singleEvents=True,
                    orderBy='startTime'
                ).execute()

                for event in events_result.get('items', []):
                    start = event.get('start', {})
                    end = event.get('end', {})

                    if 'date' in start:

                        start_date = start['date']
                        start_time = None
                        end_date = end.get('date', start_date)
                        end_time = None
                        all_day = True
                    else:

                        start_dt = start.get('dateTime', '')
                        end_dt = end.get('dateTime', '')
                        start_date = start_dt[:10] if start_dt else ''
                        start_time = start_dt[11:16] if len(start_dt) > 11 else ''
                        end_date = end_dt[:10] if end_dt else start_date
                        end_time = end_dt[11:16] if len(end_dt) > 11 else ''
                        all_day = False

                    all_events.append({
                        "id": event.get('id', ''),
                        "title": event.get('summary', '(No title)'),
                        "start_date": start_date,
                        "start_time": start_time,
                        "end_date": end_date,
                        "end_time": end_time,
                        "all_day": all_day,
                        "location": event.get('location', ''),
                        "description": event.get('description', ''),
                        "calendar": cal_name,
                        "calendar_id": cal_id,
                        "calendar_color": cal_color,
                        "source": "google",
                        "recurring_event_id": event.get('recurringEventId', None)
                    })
            except Exception:

                continue

        all_events.sort(key=lambda e: (e['start_date'], e['start_time'] or '00:00'))

        return {
            "success": True,
            "events": all_events,
            "account": email,
            "calendars": len(calendars)
        }

    except Exception as e:
        error_msg = str(e)
        if 'insufficient' in error_msg.lower() or 'scope' in error_msg.lower():
            return {
                "success": False,
                "error": "scope_needed",
                "message": "Calendar access not granted. Please sign out and sign in again to grant calendar permission.",
                "events": []
            }
        logging.error(f"Google Calendar error: {error_msg}")
        return {
            "success": False,
            "error": "api_error",
            "message": "Failed to fetch calendar events",
            "events": []
        }

def get_google_calendars(account_email: str = None) -> Dict:

    tokens = load_tokens()

    if not tokens:
        return {"success": False, "error": "No Google account connected", "calendars": []}

    if account_email and account_email in tokens:
        email = account_email
    else:
        email = list(tokens.keys())[0]

    creds = get_credentials(email)
    if not creds:
        return {"success": False, "error": "Not authenticated", "calendars": []}

    try:
        service = build('calendar', 'v3', credentials=creds)
        calendar_list = service.calendarList().list().execute()
        calendars = calendar_list.get('items', [])

        result = []
        for cal in calendars:
            result.append({
                "id": cal.get('id'),
                "name": cal.get('summary', 'Calendar'),
                "color": cal.get('backgroundColor', '#4285f4'),
                "primary": cal.get('primary', False),
                "access_role": cal.get('accessRole', 'reader')
            })

        return {"success": True, "calendars": result, "account": email}

    except Exception as e:
        logging.error(f"Google calendars error: {e}")
        return {"success": False, "error": "Google API error", "calendars": []}

def create_google_calendar_event(
    title: str,
    start_date: str,
    start_time: str = None,
    end_date: str = None,
    end_time: str = None,
    description: str = None,
    location: str = None,
    calendar_id: str = 'primary',
    account_email: str = None
) -> Dict:

    tokens = load_tokens()

    if not tokens:
        return {"success": False, "error": "No Google account connected"}

    if account_email and account_email in tokens:
        email = account_email
    else:
        email = list(tokens.keys())[0]

    creds = get_credentials(email)
    if not creds:
        return {"success": False, "error": "Not authenticated"}

    try:
        service = build('calendar', 'v3', credentials=creds)

        event = {
            'summary': title,
            'description': description or '',
            'location': location or ''
        }

        if start_time:

            start_datetime = f"{start_date}T{start_time}:00"
            end_date = end_date or start_date
            end_time = end_time or start_time
            end_datetime = f"{end_date}T{end_time}:00"

            event['start'] = {'dateTime': start_datetime, 'timeZone': 'Europe/Berlin'}
            event['end'] = {'dateTime': end_datetime, 'timeZone': 'Europe/Berlin'}
        else:

            end_date = end_date or start_date
            event['start'] = {'date': start_date}
            event['end'] = {'date': end_date}

        created_event = service.events().insert(
            calendarId=calendar_id,
            body=event
        ).execute()

        return {
            "success": True,
            "event_id": created_event.get('id'),
            "html_link": created_event.get('htmlLink'),
            "message": "Event created successfully"
        }

    except Exception as e:
        logging.error(f"Google calendar create event error: {e}")
        return {"success": False, "error": "Failed to create calendar event"}

def update_google_calendar_event(
    event_id: str,
    title: str = None,
    start_date: str = None,
    start_time: str = None,
    end_date: str = None,
    end_time: str = None,
    description: str = None,
    location: str = None,
    calendar_id: str = 'primary',
    account_email: str = None
) -> Dict:

    tokens = load_tokens()

    if not tokens:
        return {"success": False, "error": "No Google account connected"}

    if account_email and account_email in tokens:
        email = account_email
    else:
        email = list(tokens.keys())[0]

    creds = get_credentials(email)
    if not creds:
        return {"success": False, "error": "Not authenticated"}

    try:
        service = build('calendar', 'v3', credentials=creds)

        existing_event = service.events().get(
            calendarId=calendar_id,
            eventId=event_id
        ).execute()

        if title is not None:
            existing_event['summary'] = title
        if description is not None:
            existing_event['description'] = description
        if location is not None:
            existing_event['location'] = location

        if start_date:
            if start_time:
                start_datetime = f"{start_date}T{start_time}:00"
                end_date = end_date or start_date
                end_time = end_time or start_time
                end_datetime = f"{end_date}T{end_time}:00"

                existing_event['start'] = {'dateTime': start_datetime, 'timeZone': 'Europe/Berlin'}
                existing_event['end'] = {'dateTime': end_datetime, 'timeZone': 'Europe/Berlin'}
            else:
                end_date = end_date or start_date
                existing_event['start'] = {'date': start_date}
                existing_event['end'] = {'date': end_date}

        updated_event = service.events().update(
            calendarId=calendar_id,
            eventId=event_id,
            body=existing_event
        ).execute()

        return {
            "success": True,
            "event_id": updated_event.get('id'),
            "message": "Event updated successfully"
        }

    except Exception as e:
        logging.error(f"Google calendar update event error: {e}")
        return {"success": False, "error": "Failed to update calendar event"}

def delete_google_calendar_event(
    event_id: str,
    calendar_id: str = 'primary',
    account_email: str = None,
    delete_all_occurrences: bool = False,
    recurring_event_id: str = None
) -> Dict:
    tokens = load_tokens()

    if not tokens:
        return {"success": False, "error": "No Google account connected"}

    if account_email and account_email in tokens:
        email = account_email
    else:
        email = list(tokens.keys())[0]

    creds = get_credentials(email)
    if not creds:
        return {"success": False, "error": "Not authenticated"}

    try:
        service = build('calendar', 'v3', credentials=creds)

        if delete_all_occurrences and recurring_event_id:
            service.events().delete(
                calendarId=calendar_id,
                eventId=recurring_event_id
            ).execute()
            return {"success": True, "message": "Alle Wiederholungen gelöscht"}
        else:
            service.events().delete(
                calendarId=calendar_id,
                eventId=event_id
            ).execute()
            return {"success": True, "message": "Termin gelöscht"}

    except Exception as e:
        logging.error(f"Google calendar delete event error: {e}")
        return {"success": False, "error": "Failed to delete calendar event"}

def delete_gmail_message(email: str, msg_id: str, permanent: bool = False) -> Dict:

    creds = get_credentials(email)
    if not creds:
        return {"success": False, "error": "Not authenticated"}

    try:
        service = build('gmail', 'v1', credentials=creds)

        if permanent:

            service.users().messages().delete(
                userId='me',
                id=msg_id
            ).execute()
        else:

            service.users().messages().trash(
                userId='me',
                id=msg_id
            ).execute()

        return {"success": True, "message": "Email deleted successfully"}

    except Exception as e:
        logging.error(f"Gmail delete error: {e}")
        return {"success": False, "error": "Failed to delete email"}
