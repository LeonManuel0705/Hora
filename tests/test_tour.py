# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import pytest

from app import database as db


@pytest.fixture
def db_path(tmp_path, monkeypatch):
    path = tmp_path / "hub.db"
    monkeypatch.setattr(db, "DATABASE_PATH", str(path))
    db.init_db()
    return path


@pytest.fixture
def client(db_path):
    from app import app as app_module
    from app.app import app

    app.config["TESTING"] = True
    with app.test_client() as client:
        # A /hub visit no longer hands out the web session on its own; the token
        # establishes it once, exactly as a browser does.
        client.get(f"/hub?token={app_module.API_TOKEN}")
        yield client


def test_tour_state_starts_empty(db_path):
    assert db.get_tour_state() is None


def test_tour_state_is_saved(db_path):
    db.save_tour_state("skipped")
    assert db.get_tour_state() == "skipped"
    db.save_tour_state("done")
    assert db.get_tour_state() == "done"


def test_tour_state_keeps_the_theme(db_path):
    db.save_user_theme("light")
    db.save_tour_state("done")
    assert db.get_user_theme() == "light"
    assert db.get_tour_state() == "done"


def test_unknown_tour_state_is_rejected(db_path):
    with pytest.raises(ValueError):
        db.save_tour_state("halfway")


def test_has_hub_tasks(db_path):
    assert not db.has_hub_tasks()
    db.create_hub_task(title="Vokabeln lernen")
    assert db.has_hub_tasks()


def test_tour_api_round_trip(client):
    assert client.get("/api/hub/tour").get_json() == {"success": True, "state": None}
    response = client.post("/api/hub/tour", json={"state": "done"})
    assert response.status_code == 200
    assert client.get("/api/hub/tour").get_json()["state"] == "done"


def test_tour_api_rejects_unknown_states(client):
    response = client.post("/api/hub/tour", json={"state": "reset"})
    assert response.status_code == 400
    assert client.get("/api/hub/tour").get_json()["state"] is None


def test_tour_api_needs_the_session(db_path):
    from app.app import app

    with app.test_client() as anonymous:
        assert anonymous.post("/api/hub/tour", json={"state": "done"}).status_code == 401


def test_hub_starts_the_tour_only_for_new_users(client):
    assert b'data-tour-auto="1"' in client.get("/hub").data
    db.create_hub_task(title="Vokabeln lernen")
    assert b'data-tour-auto="0"' in client.get("/hub").data


def test_hub_stops_offering_the_tour_once_it_ran(client):
    client.post("/api/hub/tour", json={"state": "skipped"})
    assert b'data-tour-auto="0"' in client.get("/hub").data
