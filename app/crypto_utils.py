# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import os
import json
import base64
import hashlib
from pathlib import Path
from cryptography.fernet import Fernet

from .paths import DATA_DIR

def _get_secret_key() -> str:
    key = os.environ.get('SECRET_KEY')
    if key:
        return key
    key_file = DATA_DIR / '.secret_key'
    if key_file.exists():
        return key_file.read_text().strip()
    key = os.urandom(32).hex()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(key_file), os.O_CREAT | os.O_WRONLY, 0o600)
    os.write(fd, key.encode())
    os.close(fd)
    print("WARNING: No SECRET_KEY env var set. Generated a local key at data/.secret_key")
    return key


_PBKDF2_ITERATIONS = 600_000
_LEGACY_ITERATIONS = 100_000
_STATIC_SALT = b'nexus-salt-v1'
_SALT_PREFIX = 'ENC2:'
_LEGACY_SALT_PREFIX = 'NEXUS2:'


def _derive_fernet_key(secret: str, salt: bytes, iterations: int = _PBKDF2_ITERATIONS) -> bytes:
    dk = hashlib.pbkdf2_hmac('sha256', secret.encode(), salt, iterations)
    return base64.urlsafe_b64encode(dk)


def _get_fernet_with_salt(salt: bytes, iterations: int = _PBKDF2_ITERATIONS) -> Fernet:
    return Fernet(_derive_fernet_key(_get_secret_key(), salt, iterations))


def get_fernet(iterations: int = _PBKDF2_ITERATIONS) -> Fernet:
    """Legacy: get Fernet with static salt. Used for backward-compatible decryption."""
    return _get_fernet_with_salt(_STATIC_SALT, iterations)


def encrypt_json(data: dict) -> str:
    """Encrypt JSON data with a random per-encryption salt."""
    salt = os.urandom(16)
    fernet = _get_fernet_with_salt(salt)
    plaintext = json.dumps(data).encode('utf-8')
    ciphertext = fernet.encrypt(plaintext).decode('utf-8')
    salt_b64 = base64.urlsafe_b64encode(salt).decode('utf-8')
    return f'{_SALT_PREFIX}{salt_b64}:{ciphertext}'


def decrypt_json(token: str) -> dict:
    """Decrypt with per-file salt (new) or static salt (legacy); auto-migrates."""
    prefix = next((p for p in (_SALT_PREFIX, _LEGACY_SALT_PREFIX) if token.startswith(p)), None)
    if prefix:
        rest = token[len(prefix):]
        salt_b64, ciphertext = rest.split(':', 1)
        salt = base64.urlsafe_b64decode(salt_b64)
        plaintext = _get_fernet_with_salt(salt).decrypt(ciphertext.encode('utf-8'))
        return json.loads(plaintext.decode('utf-8'))
    try:
        plaintext = get_fernet().decrypt(token.encode('utf-8'))
        return json.loads(plaintext.decode('utf-8'))
    except Exception:
        plaintext = get_fernet(_LEGACY_ITERATIONS).decrypt(token.encode('utf-8'))
        return json.loads(plaintext.decode('utf-8'))


def encrypt_file(data: dict, filepath: Path):
    filepath.parent.mkdir(parents=True, exist_ok=True)
    encrypted = encrypt_json(data)
    tmp_path = filepath.with_suffix('.tmp')
    fd = os.open(str(tmp_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(encrypted)
        os.rename(str(tmp_path), str(filepath))
    except BaseException:
        try:
            os.unlink(str(tmp_path))
        except OSError:
            pass
        raise


def decrypt_file(filepath: Path) -> dict:
    if not filepath.exists():
        return None
    content = filepath.read_text().strip()
    if not content:
        return None
    if content.startswith('{') or content.startswith('['):
        data = json.loads(content)
        encrypt_file(data, filepath)
        return data
    data = decrypt_json(content)
    if not content.startswith(_SALT_PREFIX):
        encrypt_file(data, filepath)
    return data
