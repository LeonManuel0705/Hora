# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import os
import json
import base64
import hashlib
import tempfile
from pathlib import Path
from cryptography.fernet import Fernet

from .paths import DATA_DIR

_MIN_SECRET_LENGTH = 32

_PLACEHOLDER_SECRETS = {
    'your-secret-key-here',
    'secret-key-change-me',
    'changeme',
    'please-change-me',
}


class InsecureSecretError(RuntimeError):
    """The configured SECRET_KEY is a placeholder or too short to derive from."""


class PlaintextCredentialError(RuntimeError):
    """A credential file was found unencrypted and was not adopted."""


def _validate_secret(key: str, source: str) -> str:
    if key.strip().lower() in _PLACEHOLDER_SECRETS:
        raise InsecureSecretError(
            f"SECRET_KEY from {source} is the example placeholder. Remove it so a "
            f"random key is generated in data/.secret_key, or set a real one."
        )
    if len(key) < _MIN_SECRET_LENGTH:
        raise InsecureSecretError(
            f"SECRET_KEY from {source} is {len(key)} characters; at least "
            f"{_MIN_SECRET_LENGTH} are required."
        )
    return key


def _get_secret_key() -> str:
    key = os.environ.get('SECRET_KEY')
    if key:
        return _validate_secret(key, 'the environment')
    key_file = DATA_DIR / '.secret_key'
    if key_file.exists():
        return _validate_secret(key_file.read_text().strip(), str(key_file))
    key = os.urandom(32).hex()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    # O_EXCL so a pre-created path is never written through, O_NOFOLLOW so a
    # symlink is refused rather than followed. exists() above returns False for
    # a dangling symlink, which is exactly how the key used to be redirected.
    try:
        fd = os.open(str(key_file), os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        return _validate_secret(key_file.read_text().strip(), str(key_file))
    try:
        os.write(fd, key.encode())
    finally:
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
    # mkstemp creates with O_EXCL and 0600 under a random name, so a pre-created
    # path cannot be written through and a stale .tmp cannot collide.
    fd, tmp_name = tempfile.mkstemp(dir=str(filepath.parent), prefix='.enc-', suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(encrypted)
        os.chmod(tmp_name, 0o600)
        os.replace(tmp_name, str(filepath))
    except BaseException:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


# Adopting unencrypted JSON is a migration convenience, but for these files it
# would let anyone who can write one file hand themselves a credential the app
# then re-encrypts under the real key and treats as its own.
_NEVER_ADOPT_PLAINTEXT = {
    '.api_token',
    'api_token.json',
    'iserv_credentials.json',
    'email_config.json',
    'caldav_accounts.json',
    'google_tokens.json',
    'google_credentials.json',
    'assistant_config.json',
}


def decrypt_file(filepath: Path) -> dict:
    if not filepath.exists():
        return None
    content = filepath.read_text().strip()
    if not content:
        return None
    if content.startswith('{') or content.startswith('['):
        if filepath.name in _NEVER_ADOPT_PLAINTEXT:
            raise PlaintextCredentialError(
                f"{filepath.name} is unencrypted and was not loaded. Delete it and "
                f"enter the credentials again so they are stored encrypted."
            )
        data = json.loads(content)
        encrypt_file(data, filepath)
        return data
    data = decrypt_json(content)
    if not content.startswith(_SALT_PREFIX):
        encrypt_file(data, filepath)
    return data
