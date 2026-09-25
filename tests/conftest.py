# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import atexit
import os
import shutil
import tempfile
from pathlib import Path

import pytest

_TEST_ROOT = tempfile.mkdtemp(prefix="hub-tests-")
os.environ["HUB_DATA_DIR"] = str(Path(_TEST_ROOT) / "data")
atexit.register(shutil.rmtree, _TEST_ROOT, True)


@pytest.fixture(autouse=True)
def secret_key(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", "test-secret-key-for-crypto-utils")
