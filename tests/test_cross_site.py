# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import pytest

REFUSED = {'error': 'Cross-site request refused'}


@pytest.fixture
def hub(monkeypatch):
    from app import app as hub

    monkeypatch.setattr(hub, 'DESKTOP_TOKEN', None)
    hub.app.config['TESTING'] = True
    return hub


@pytest.fixture
def client(hub):
    with hub.app.test_client() as client:
        client.get(f'/hub?token={hub.API_TOKEN}')
        yield client


@pytest.mark.parametrize('site', [None, 'same-origin', 'none'])
def test_own_and_direct_requests_pass(client, site):
    headers = {'Sec-Fetch-Site': site} if site else {}
    assert client.get('/api/ping', headers=headers).status_code == 204


@pytest.mark.parametrize('site', ['cross-site', 'same-site'])
def test_requests_from_other_sites_are_refused(client, site):
    response = client.get('/api/ping', headers={'Sec-Fetch-Site': site})
    assert response.status_code == 403 and response.get_json() == REFUSED


def test_a_foreign_page_cannot_open_a_mail_and_mark_it_read(client):
    response = client.get('/api/email/message/anna@schule.de/7', headers={'Sec-Fetch-Site': 'cross-site'})
    assert response.status_code == 403 and response.get_json() == REFUSED


def test_configured_cors_origins_stay_allowed(client, hub):
    headers = {'Sec-Fetch-Site': 'cross-site', 'Origin': hub.ALLOWED_ORIGINS[0]}
    assert client.get('/api/ping', headers=headers).status_code == 204


@pytest.mark.parametrize('origin', ['http://evil.example', 'null', 'http://[', 'http://localhost.evil.example'])
def test_writes_from_foreign_origins_are_refused(client, origin):
    response = client.post('/api/desktop-login-code', headers={'Origin': origin})
    assert response.status_code == 403 and response.get_json() == REFUSED


def test_writes_from_the_own_origin_pass(client):
    assert client.post('/api/desktop-login-code', headers={'Origin': 'http://localhost'}).status_code == 404


def test_google_can_still_redirect_back(client):
    response = client.get('/api/email/google/oauth-callback?code=x&state=y', headers={'Sec-Fetch-Site': 'cross-site'})
    assert response.get_json(silent=True) != REFUSED
