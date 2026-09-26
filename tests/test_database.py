# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import logging
import sqlite3

import pytest

from app import database as db


@pytest.fixture
def db_path(tmp_path, monkeypatch):
    path = tmp_path / "hub.db"
    monkeypatch.setattr(db, "DATABASE_PATH", str(path))
    return path


def table_names(path):
    conn = sqlite3.connect(path)
    try:
        return {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    finally:
        conn.close()


def create_retired_tables(path, filled):
    conn = sqlite3.connect(path)
    try:
        for table in db.RETIRED_TABLES:
            conn.execute(f"CREATE TABLE {table} (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, user_id TEXT)")
            if table in filled:
                conn.execute(f"INSERT INTO {table} (name) VALUES ('kept')")
        conn.commit()
    finally:
        conn.close()


def test_new_database_has_no_retired_tables(db_path):
    db.init_db()
    names = table_names(db_path)
    assert "hub_tasks" in names
    assert names.isdisjoint(db.RETIRED_TABLES)


def test_empty_retired_tables_are_dropped(db_path):
    create_retired_tables(db_path, filled=())
    db.init_db()
    assert table_names(db_path).isdisjoint(db.RETIRED_TABLES)


def test_filled_retired_tables_are_kept_with_a_warning(db_path, caplog):
    create_retired_tables(db_path, filled=("hub_projects",))
    with caplog.at_level(logging.WARNING, logger=db.__name__):
        db.init_db()
    names = table_names(db_path)
    assert "hub_projects" in names
    assert "hub_knowledge" not in names
    assert "hub_drawings" not in names
    assert "hub_projects" in caplog.text

    db.init_db()
    conn = sqlite3.connect(db_path)
    try:
        assert conn.execute("SELECT name FROM hub_projects").fetchall() == [("kept",)]
    finally:
        conn.close()
