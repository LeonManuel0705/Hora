# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import json
import base64
import hashlib
from pathlib import Path

import pytest
from cryptography.fernet import Fernet

from app.crypto_utils import (
    encrypt_json,
    decrypt_json,
    encrypt_file,
    decrypt_file,
    _SALT_PREFIX,
    _LEGACY_SALT_PREFIX,
    _STATIC_SALT,
    _LEGACY_ITERATIONS,
    _PBKDF2_ITERATIONS,
    _derive_fernet_key,
)


class TestEncryptDecryptJson:
    def test_roundtrip_dict(self):
        data = {"key": "value", "number": 42}
        encrypted = encrypt_json(data)
        assert decrypt_json(encrypted) == data

    def test_roundtrip_list(self):
        data = [{"a": 1}, {"b": 2}]
        encrypted = encrypt_json(data)
        assert decrypt_json(encrypted) == data

    def test_roundtrip_empty_dict(self):
        data = {}
        encrypted = encrypt_json(data)
        assert decrypt_json(encrypted) == data

    def test_encrypted_has_salt_prefix(self):
        encrypted = encrypt_json({"test": True})
        assert encrypted.startswith(_SALT_PREFIX)

    def test_different_ciphertext_each_call(self):
        data = {"same": "data"}
        a = encrypt_json(data)
        b = encrypt_json(data)
        assert a != b


class TestEncryptDecryptFile:
    def test_roundtrip(self, tmp_path):
        filepath = tmp_path / "test.enc"
        data = {"hello": "world", "nested": {"a": [1, 2, 3]}}
        encrypt_file(data, filepath)
        assert filepath.exists()
        assert decrypt_file(filepath) == data

    def test_file_permissions(self, tmp_path):
        filepath = tmp_path / "test.enc"
        encrypt_file({"x": 1}, filepath)
        mode = filepath.stat().st_mode & 0o777
        assert mode == 0o600

    def test_creates_parent_dirs(self, tmp_path):
        filepath = tmp_path / "nested" / "dirs" / "test.enc"
        encrypt_file({"x": 1}, filepath)
        assert filepath.exists()

    def test_nonexistent_file_returns_none(self, tmp_path):
        assert decrypt_file(tmp_path / "missing.enc") is None

    def test_empty_file_returns_none(self, tmp_path):
        filepath = tmp_path / "empty.enc"
        filepath.write_text("")
        assert decrypt_file(filepath) is None


class TestPlaintextAutoMigration:
    def test_dict_plaintext_migrated(self, tmp_path):
        filepath = tmp_path / "plain.json"
        data = {"username": "alice", "token": "abc123"}
        filepath.write_text(json.dumps(data))

        result = decrypt_file(filepath)
        assert result == data

        raw = filepath.read_text()
        assert raw.startswith(_SALT_PREFIX)
        assert decrypt_json(raw) == data

    def test_list_plaintext_migrated(self, tmp_path):
        filepath = tmp_path / "plain.json"
        data = [{"id": 1}, {"id": 2}]
        filepath.write_text(json.dumps(data))

        result = decrypt_file(filepath)
        assert result == data

        raw = filepath.read_text()
        assert raw.startswith(_SALT_PREFIX)


class TestLegacyIterationMigration:
    def _encrypt_legacy(self, data: dict) -> str:
        """Encrypt using the legacy static-salt scheme (no salt prefix)."""
        secret = "test-secret-key-for-crypto-utils"
        key = _derive_fernet_key(secret, _STATIC_SALT, _LEGACY_ITERATIONS)
        fernet = Fernet(key)
        plaintext = json.dumps(data).encode("utf-8")
        return fernet.encrypt(plaintext).decode("utf-8")

    def test_decrypt_json_handles_legacy(self):
        data = {"legacy": True}
        token = self._encrypt_legacy(data)
        assert not token.startswith(_SALT_PREFIX)
        assert decrypt_json(token) == data

    def test_file_re_encrypts_with_current_iterations(self, tmp_path):
        filepath = tmp_path / "legacy.enc"
        data = {"migrated": False}
        token = self._encrypt_legacy(data)
        filepath.write_text(token)

        result = decrypt_file(filepath)
        assert result == data

        raw = filepath.read_text()
        assert raw.startswith(_SALT_PREFIX)
        assert decrypt_json(raw) == data


class TestLegacySaltPrefixMigration:
    def _legacy_token(self, data: dict) -> str:
        return _LEGACY_SALT_PREFIX + encrypt_json(data)[len(_SALT_PREFIX):]

    def test_decrypt_json_reads_legacy_prefix(self):
        data = {"prefix": "legacy"}
        assert decrypt_json(self._legacy_token(data)) == data

    def test_file_is_rewritten_with_current_prefix(self, tmp_path):
        filepath = tmp_path / "legacy_prefix.enc"
        data = {"migrated": False}
        filepath.write_text(self._legacy_token(data))

        assert decrypt_file(filepath) == data

        raw = filepath.read_text()
        assert raw.startswith(_SALT_PREFIX)
        assert decrypt_json(raw) == data
