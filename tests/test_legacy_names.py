# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import json
import subprocess
import sys
from pathlib import Path

from app import brand
from app import database as db
from app import paths

ROOT = Path(__file__).resolve().parent.parent


def test_previous_names_come_from_brand_json():
    data = json.loads((ROOT / "brand" / "brand.json").read_text(encoding="utf-8"))
    assert tuple(data["previousNames"]) == brand.PREVIOUS_NAMES
    assert data["name"] not in data["previousNames"]


def test_current_prefix_wins_over_previous(monkeypatch):
    monkeypatch.setattr(brand, "PREVIOUS_NAMES", ("Nexus",))
    monkeypatch.delenv("HUB_DATA_DIR", raising=False)
    monkeypatch.setenv("NEXUS_DATA_DIR", "/alt")
    assert paths.env("DATA_DIR") == "/alt"
    monkeypatch.setenv("HUB_DATA_DIR", "/neu")
    assert paths.env("DATA_DIR") == "/neu"
    monkeypatch.setenv("HUB_DATA_DIR", "")
    assert paths.env("DATA_DIR") == "/alt"
    monkeypatch.delenv("NEXUS_DATA_DIR")
    assert paths.env("DATA_DIR", "standard") == "standard"


def test_odd_previous_names_never_become_prefixes(monkeypatch):
    monkeypatch.setattr(brand, "PREVIOUS_NAMES", ("1 Bad", "---", "Nexus"))
    monkeypatch.delenv("HUB_PORT", raising=False)
    monkeypatch.setenv("1_BAD_PORT", "1")
    monkeypatch.setenv("NEXUS_PORT", "6060")
    assert paths.env("PORT") == "6060"


def test_bind_address_ignores_the_old_prefix():
    source = (ROOT / "app" / "app.py").read_text(encoding="utf-8")
    assert "os.environ.get('HUB_HOST', '127.0.0.1')" in source
    assert "env('HOST'" not in source


def test_old_database_is_adopted_once(tmp_path, monkeypatch):
    monkeypatch.setattr(brand, "PREVIOUS_NAMES", ("Nexus",))
    monkeypatch.setattr(db, "DATA_DIR", str(tmp_path))
    monkeypatch.setattr(db, "DATABASE_PATH", str(tmp_path / "hub.db"))
    (tmp_path / "nexus.db").write_text("alt")
    (tmp_path / "nexus.db-wal").write_text("wal")
    db._adopt_previous_database()
    assert (tmp_path / "hub.db").read_text() == "alt"
    assert (tmp_path / "hub.db-wal").read_text() == "wal"
    assert not (tmp_path / "nexus.db").exists()


def test_existing_database_is_never_replaced(tmp_path, monkeypatch):
    monkeypatch.setattr(brand, "PREVIOUS_NAMES", ("Nexus",))
    monkeypatch.setattr(db, "DATA_DIR", str(tmp_path))
    monkeypatch.setattr(db, "DATABASE_PATH", str(tmp_path / "hub.db"))
    (tmp_path / "hub.db").write_text("neu")
    (tmp_path / "nexus.db").write_text("alt")
    db._adopt_previous_database()
    assert (tmp_path / "hub.db").read_text() == "neu"
    assert (tmp_path / "nexus.db").read_text() == "alt"


def test_brand_files_carry_the_previous_names():
    result = subprocess.run([sys.executable, str(ROOT / "scripts" / "apply_brand.py"), "--check"], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
