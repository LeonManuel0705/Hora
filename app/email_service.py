# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import os
import base64
import imaplib
import logging
import socket
import smtplib
import ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.utils import parsedate_to_datetime, formatdate
from email.header import decode_header
from typing import Dict, List, Optional
from datetime import datetime
import re
from pathlib import Path

from .crypto_utils import encrypt_file, decrypt_file

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.environ.get("HUB_DATA_DIR") or os.path.join(PROJECT_ROOT, "data")
os.makedirs(DATA_DIR, exist_ok=True)
EMAIL_CONFIG_PATH = Path(DATA_DIR) / "email_config.json"
EMAIL_TIMEOUT = 30

# imaplib and smtplib fall back to ssl._create_stdlib_context() when no context
# is passed, and that context is CERT_NONE with check_hostname off.
_TLS_CONTEXT = ssl.create_default_context()

PROVIDER_SETTINGS = {
    "gmail": {
        "imap_host": "imap.gmail.com",
        "imap_port": 993,
        "smtp_host": "smtp.gmail.com",
        "smtp_port": 587,
        "requires_app_password": True
    },
    "outlook": {
        "imap_host": "outlook.office365.com",
        "imap_port": 993,
        "smtp_host": "smtp.office365.com",
        "smtp_port": 587,
        "requires_app_password": False
    },
    "iserv": {
        "imap_host": None,
        "imap_port": 993,
        "smtp_host": None,
        "smtp_port": 587,
        "requires_app_password": False
    }
}

_METADATA_IPS = {'169.254.169.254', 'fd00:ec2::254'}


def _check_blocked_ip(addr) -> str:
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


def _validate_email_host(hostname: str) -> str:
    """Validate an email hostname to prevent SSRF. Returns error message or None if valid.

    Blocks loopback, unspecified (0.0.0.0), and cloud metadata endpoints.
    Allows RFC 1918 / link-local so self-hosted mail servers on a LAN
    (e.g. IServ mail on a school network) remain reachable.
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

def get_iserv_settings(email: str) -> Dict:

    domain = email.split('@')[1] if '@' in email else None
    if not domain:
        return None

    host_error = _validate_email_host(domain)
    if host_error:
        return None

    return {
        "imap_host": domain,
        "imap_port": 993,
        "smtp_host": domain,
        "smtp_port": 587,
        "requires_app_password": False
    }

def get_provider_settings(provider: str, email: str) -> Optional[Dict]:

    if provider == "iserv":
        return get_iserv_settings(email)
    return PROVIDER_SETTINGS.get(provider)

def load_email_config() -> Dict:
    try:
        data = decrypt_file(EMAIL_CONFIG_PATH)
        if data:
            if not data.get("_migrated_v2"):
                for account in data.get("accounts", []):
                    pw = account.get("password", "")
                    if pw:
                        try:
                            account["password"] = base64.b64decode(pw).decode()
                        except Exception:
                            pass
                data["_migrated_v2"] = True
                save_email_config(data)
            return data
        return {"accounts": []}
    except Exception:
        return {"accounts": []}

def save_email_config(config: Dict) -> bool:
    try:
        encrypt_file(config, EMAIL_CONFIG_PATH)
        return True
    except Exception:
        return False

def add_email_account(email: str, password: str, provider: str) -> Dict:
    if provider not in PROVIDER_SETTINGS:
        return {"success": False, "error": "Unsupported provider"}

    if provider == "iserv":
        settings = get_iserv_settings(email)
        if not settings:
            return {"success": False, "error": "Invalid email address for IServ"}
    else:
        settings = PROVIDER_SETTINGS[provider]

    try:
        imap = imaplib.IMAP4_SSL(settings["imap_host"], settings["imap_port"],
                                  ssl_context=_TLS_CONTEXT, timeout=EMAIL_TIMEOUT)
        imap.login(email, password)
        imap.logout()
    except imaplib.IMAP4.error as e:
        error_msg = str(e)
        if "AUTHENTICATIONFAILED" in error_msg or "Invalid credentials" in error_msg:
            if provider == "gmail":
                return {"success": False, "error": "Authentication failed. For Gmail, you need to use an App Password. Go to Google Account > Security > 2-Step Verification > App Passwords."}
            return {"success": False, "error": "Authentication failed. Check your email and password."}
        logging.error(f"Email IMAP error: {error_msg}")
        return {"success": False, "error": "Connection failed"}
    except Exception as e:
        logging.error(f"Email connection error: {e}")
        return {"success": False, "error": "Connection failed"}

    config = load_email_config()
    existing = next((a for a in config["accounts"] if a["email"] == email), None)
    if existing:
        existing["password"] = password
        existing["provider"] = provider
    else:
        config["accounts"].append({
            "email": email,
            "password": password,
            "provider": provider,
            "added_at": datetime.now().isoformat()
        })

    save_email_config(config)
    return {"success": True, "message": "Account added successfully"}

def remove_email_account(email: str) -> bool:
    config = load_email_config()
    config["accounts"] = [a for a in config["accounts"] if a["email"] != email]
    return save_email_config(config)

def get_email_accounts() -> List[Dict]:
    config = load_email_config()
    return [{"email": a["email"], "provider": a["provider"]} for a in config["accounts"]]

def decode_email_header(header: str) -> str:
    if not header:
        return ""
    decoded_parts = []
    for part, charset in decode_header(header):
        if isinstance(part, bytes):
            try:
                decoded_parts.append(part.decode(charset or 'utf-8', errors='replace'))
            except Exception:
                decoded_parts.append(part.decode('utf-8', errors='replace'))
        else:
            decoded_parts.append(part)
    return ' '.join(decoded_parts)

def extract_email_address(from_header: str) -> str:
    match = re.search(r'<([^>]+)>', from_header)
    if match:
        return match.group(1)
    return from_header.strip()

def extract_sender_name(from_header: str) -> str:
    match = re.match(r'^([^<]+)<', from_header)
    if match:
        return match.group(1).strip().strip('"')
    return from_header.split('@')[0]

def get_email_body(msg) -> str:
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            content_disposition = str(part.get("Content-Disposition", ""))
            if content_type == "text/plain" and "attachment" not in content_disposition:
                try:
                    payload = part.get_payload(decode=True)
                    charset = part.get_content_charset() or 'utf-8'
                    body = payload.decode(charset, errors='replace')
                    break
                except Exception:
                    pass
            elif content_type == "text/html" and "attachment" not in content_disposition and not body:
                try:
                    payload = part.get_payload(decode=True)
                    charset = part.get_content_charset() or 'utf-8'
                    html = payload.decode(charset, errors='replace')
                    body = re.sub(r'<[^>]+>', '', html)
                    body = re.sub(r'\s+', ' ', body).strip()
                except Exception:
                    pass
    else:
        try:
            payload = msg.get_payload(decode=True)
            charset = msg.get_content_charset() or 'utf-8'
            body = payload.decode(charset, errors='replace')
        except Exception:
            body = str(msg.get_payload())

    return body[:5000]

def _validate_folder(folder: str) -> str:
    """Validate IMAP folder name to prevent injection."""
    if not folder or not re.fullmatch(r'[a-zA-Z0-9_./\- \[\]äöüÄÖÜß]+', folder):
        raise ValueError('Invalid folder name')
    if len(folder) > 200:
        raise ValueError('Folder name too long')
    return folder

def fetch_emails(email: str, folder: str = "INBOX", limit: int = 20) -> Dict:
    config = load_email_config()
    account = next((a for a in config["accounts"] if a["email"] == email), None)
    if not account:
        return {"success": False, "error": "Account not found"}

    provider = account["provider"]
    settings = get_provider_settings(provider, email)
    if not settings:
        return {"success": False, "error": "Unknown provider"}

    try:
        password = account["password"]
        imap = imaplib.IMAP4_SSL(settings["imap_host"], settings["imap_port"],
                                  ssl_context=_TLS_CONTEXT, timeout=EMAIL_TIMEOUT)
        imap.login(email, password)

        _validate_folder(folder)
        status, _ = imap.select(folder, readonly=True)
        if status != "OK":
            imap.logout()
            return {"success": False, "error": "Ordner konnte nicht ausgewählt werden"}

        status, messages = imap.search(None, "ALL")
        if status != "OK":
            imap.logout()
            return {"success": False, "error": "Could not search messages"}

        message_ids = messages[0].split()
        message_ids = message_ids[-limit:] if len(message_ids) > limit else message_ids
        message_ids.reverse()

        emails = []
        for msg_id in message_ids:
            status, msg_data = imap.fetch(msg_id, "(RFC822 FLAGS)")
            if status != "OK":
                continue

            import email
            raw_email = msg_data[0][1]
            msg = email.message_from_bytes(raw_email)

            flags = msg_data[0][0].decode() if isinstance(msg_data[0][0], bytes) else str(msg_data[0][0])
            is_read = "\\Seen" in flags

            date_str = msg.get("Date", "")
            try:
                date_obj = parsedate_to_datetime(date_str)
                date_formatted = date_obj.strftime("%Y-%m-%d %H:%M")
            except Exception:
                date_formatted = date_str[:20]

            from_header = decode_email_header(msg.get("From", ""))
            subject = decode_email_header(msg.get("Subject", "(No Subject)"))
            body_preview = get_email_body(msg)[:200]

            emails.append({
                "id": msg_id.decode(),
                "from": extract_email_address(from_header),
                "from_name": extract_sender_name(from_header),
                "subject": subject,
                "date": date_formatted,
                "preview": body_preview,
                "read": is_read
            })

        imap.logout()
        return {"success": True, "emails": emails}

    except imaplib.IMAP4.error as e:
        logging.error(f"IMAP error fetching emails: {e}")
        return {"success": False, "error": "Failed to fetch emails"}
    except Exception as e:
        logging.error(f"Error fetching emails: {e}")
        return {"success": False, "error": "An error occurred"}

def get_email_detail(email_addr: str, msg_id: str, folder: str = "INBOX") -> Dict:
    if not re.fullmatch(r'[0-9]+', str(msg_id)):
        return {"success": False, "error": "Invalid message ID"}

    config = load_email_config()
    account = next((a for a in config["accounts"] if a["email"] == email_addr), None)
    if not account:
        return {"success": False, "error": "Account not found"}

    provider = account["provider"]
    settings = get_provider_settings(provider, email_addr)
    if not settings:
        return {"success": False, "error": "Unknown provider"}

    try:
        password = account["password"]
        imap = imaplib.IMAP4_SSL(settings["imap_host"], settings["imap_port"],
                                  ssl_context=_TLS_CONTEXT, timeout=EMAIL_TIMEOUT)
        imap.login(email_addr, password)
        _validate_folder(folder)
        imap.select(folder)

        status, msg_data = imap.fetch(msg_id.encode(), "(RFC822)")
        if status != "OK":
            imap.logout()
            return {"success": False, "error": "Could not fetch email"}

        imap.store(msg_id.encode(), '+FLAGS', '\\Seen')

        import email
        raw_email = msg_data[0][1]
        msg = email.message_from_bytes(raw_email)

        date_str = msg.get("Date", "")
        try:
            date_obj = parsedate_to_datetime(date_str)
            date_formatted = date_obj.strftime("%Y-%m-%d %H:%M")
        except Exception:
            date_formatted = date_str

        from_header = decode_email_header(msg.get("From", ""))
        to_header = decode_email_header(msg.get("To", ""))
        subject = decode_email_header(msg.get("Subject", "(No Subject)"))
        body = get_email_body(msg)

        imap.logout()

        return {
            "success": True,
            "email": {
                "id": msg_id,
                "from": extract_email_address(from_header),
                "from_name": extract_sender_name(from_header),
                "to": to_header,
                "subject": subject,
                "date": date_formatted,
                "body": body
            }
        }

    except Exception as e:
        logging.error(f"Error fetching email detail: {e}")
        return {"success": False, "error": "An error occurred"}

def _sanitize_header(value: str) -> str:
    """Strip CRLF characters to prevent email header injection."""
    return value.replace('\r', '').replace('\n', '')

def send_email(from_email: str, to_email: str, subject: str, body: str, reply_to_id: Optional[str] = None) -> Dict:
    config = load_email_config()
    account = next((a for a in config["accounts"] if a["email"] == from_email), None)
    if not account:
        return {"success": False, "error": "Account not found"}

    provider = account["provider"]
    settings = get_provider_settings(provider, from_email)
    if not settings:
        return {"success": False, "error": "Unknown provider"}

    try:
        password = account["password"]

        to_email = _sanitize_header(to_email)
        subject = _sanitize_header(subject)
        from_email = _sanitize_header(from_email)

        msg = MIMEMultipart()
        msg['From'] = from_email
        msg['To'] = to_email
        msg['Subject'] = subject
        msg['Date'] = formatdate(localtime=True)
        msg.attach(MIMEText(body, 'plain', 'utf-8'))

        server = smtplib.SMTP(settings["smtp_host"], settings["smtp_port"], timeout=EMAIL_TIMEOUT)
        server.starttls(context=_TLS_CONTEXT)
        server.login(from_email, password)
        server.sendmail(from_email, to_email.split(','), msg.as_string())
        server.quit()

        return {"success": True, "message": "Email sent successfully"}

    except smtplib.SMTPAuthenticationError:
        if provider == "gmail":
            return {"success": False, "error": "Authentication failed. For Gmail, use an App Password."}
        return {"success": False, "error": "Authentication failed. Check your credentials."}
    except Exception as e:
        logging.error(f"Error sending email: {e}")
        return {"success": False, "error": "Failed to send email"}

def delete_email(email: str, msg_id: str, folder: str = "INBOX") -> Dict:
    if not re.fullmatch(r'[0-9]+', str(msg_id)):
        return {"success": False, "error": "Invalid message ID"}

    config = load_email_config()
    account = next((a for a in config["accounts"] if a["email"] == email), None)
    if not account:
        return {"success": False, "error": "Account not found"}

    provider = account["provider"]
    settings = get_provider_settings(provider, email)
    if not settings:
        return {"success": False, "error": "Unknown provider"}

    try:
        password = account["password"]
        imap = imaplib.IMAP4_SSL(settings["imap_host"], settings["imap_port"],
                                  ssl_context=_TLS_CONTEXT, timeout=EMAIL_TIMEOUT)
        imap.login(email, password)
        _validate_folder(folder)
        imap.select(folder)

        trash_folders = ['[Gmail]/Trash', 'Trash', 'Deleted', 'Deleted Items']

        for trash in trash_folders:
            try:
                status, _ = imap.copy(msg_id.encode(), trash)
                if status == "OK":
                    break
            except Exception:
                continue

        imap.store(msg_id.encode(), '+FLAGS', '\\Deleted')
        imap.expunge()

        imap.logout()

        return {"success": True, "message": "Email deleted successfully"}

    except Exception as e:
        logging.error(f"Error deleting email: {e}")
        return {"success": False, "error": "An error occurred"}

def get_folders(email: str) -> Dict:
    config = load_email_config()
    account = next((a for a in config["accounts"] if a["email"] == email), None)
    if not account:
        return {"success": False, "error": "Account not found"}

    provider = account["provider"]
    settings = get_provider_settings(provider, email)
    if not settings:
        return {"success": False, "error": "Unknown provider"}

    try:
        password = account["password"]
        imap = imaplib.IMAP4_SSL(settings["imap_host"], settings["imap_port"],
                                  ssl_context=_TLS_CONTEXT, timeout=EMAIL_TIMEOUT)
        imap.login(email, password)

        status, folders = imap.list()
        imap.logout()

        if status != "OK":
            return {"success": False, "error": "Could not list folders"}

        folder_list = []
        for folder in folders:
            folder_str = folder.decode() if isinstance(folder, bytes) else str(folder)
            match = re.search(r'"([^"]+)"$|(\S+)$', folder_str)
            if match:
                folder_name = match.group(1) or match.group(2)
                folder_list.append(folder_name)

        return {"success": True, "folders": folder_list}

    except Exception as e:
        logging.error(f"Error fetching folders: {e}")
        return {"success": False, "error": "An error occurred"}
