# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import hashlib
import hmac
import logging
import re

import pytest

TOKEN = 'desktop-token-for-tests'
NONCE = 'ab' * 32


@pytest.fixture
def hub(monkeypatch):
    from app import app as hub

    monkeypatch.setattr(hub, 'DESKTOP_TOKEN', TOKEN)
    monkeypatch.setattr(hub, '_login_codes', {})
    hub.app.config['TESTING'] = True
    return hub


@pytest.fixture
def client(hub):
    with hub.app.test_client() as client:
        yield client


def login_code(client):
    return client.post('/api/desktop-login-code', headers={'X-Hub-Token': TOKEN}).get_json()['code']


def signed_in(client):
    with client.session_transaction() as session:
        return bool(session.get('web_auth'))


def test_handshake_proves_the_token_without_sending_it(client):
    response = client.get(f'/api/desktop-handshake?nonce={NONCE}')
    assert response.status_code == 200
    assert response.headers['Cache-Control'] == 'no-store'
    expected = hmac.new(TOKEN.encode(), f'hub-desktop-handshake:{NONCE}'.encode(), hashlib.sha256).hexdigest()
    assert response.get_json() == {'mac': expected}
    assert TOKEN not in response.get_data(as_text=True)
    assert not signed_in(client)


@pytest.mark.parametrize('nonce', ['', 'ab' * 31, 'AB' * 32, 'zz' * 32, 'ab' * 33, 'ä' * 64])
def test_handshake_rejects_malformed_nonces(client, nonce):
    assert client.get('/api/desktop-handshake', query_string={'nonce': nonce}).status_code == 400


def test_desktop_endpoints_are_absent_without_a_desktop_token(hub, client, monkeypatch):
    monkeypatch.setattr(hub, 'DESKTOP_TOKEN', None)
    assert client.get(f'/api/desktop-handshake?nonce={NONCE}').status_code == 404
    assert client.post('/api/desktop-login-code', headers={'X-Hub-Token': TOKEN}).status_code == 404


@pytest.mark.parametrize('headers', [
    {},
    {'X-Hub-Token': 'wrong'},
    {'X-Hub-Token': 'ä'},
    {'Authorization': f'Bearer {TOKEN}'},
])
def test_login_code_needs_the_desktop_token(client, headers):
    assert client.post('/api/desktop-login-code', headers=headers).status_code == 401


def test_login_code_is_post_only(client):
    assert client.get('/api/desktop-login-code', headers={'X-Hub-Token': TOKEN}).status_code == 405


def test_login_code_signs_in_once_and_leaves_the_url(hub, client):
    code = login_code(client)
    assert re.fullmatch('[0-9a-f]{64}', code)
    response = client.get(f'/hub/klassisch/tasks?tab=open&login_code={code}')
    assert response.status_code == 302
    assert response.headers['Location'].endswith('/hub/klassisch/tasks?tab=open')
    assert signed_in(client)
    with hub.app.test_client() as other:
        assert other.get(f'/hub?login_code={code}').status_code == 401
        assert not signed_in(other)


def test_expired_login_code_is_refused(hub, client, monkeypatch):
    monkeypatch.setattr(hub, 'LOGIN_CODE_TTL', 0)
    code = login_code(client)
    assert client.get(f'/hub?login_code={code}').status_code == 401
    assert not signed_in(client)


def test_only_the_newest_login_codes_stay_valid(hub, client):
    codes = [login_code(client) for _ in range(hub.LOGIN_CODE_LIMIT + 1)]
    with hub.app.test_client() as other:
        assert other.get(f'/hub?login_code={codes[0]}').status_code == 401
    assert client.get(f'/hub?login_code={codes[-1]}').status_code == 302


@pytest.mark.parametrize('value', ['', 'ä' * 64, 'AB' * 32, 'ab' * 32])
def test_unknown_or_malformed_login_code_is_refused(client, value):
    assert client.get('/hub', query_string={'login_code': value}).status_code == 401


def test_login_secrets_are_redacted_from_the_access_log(hub):
    line = '"GET /hub?login_code=aaa&x=1&token=bbb HTTP/1.1" 302 - /api/email/google/oauth-callback?code=ccc&state=s'
    record = logging.LogRecord('werkzeug', logging.INFO, __file__, 0, '%s', (line,), None)
    hub._RedactTokenFilter().filter(record)
    message = record.getMessage()
    assert 'aaa' not in message and 'bbb' not in message and 'ccc' not in message
    assert 'x=1' in message and 'state=s' in message


def test_login_code_is_burned_even_next_to_a_valid_token(hub, client):
    code = login_code(client)
    assert client.get(f'/hub?token={TOKEN}&login_code={code}').status_code == 302
    with hub.app.test_client() as other:
        assert other.get(f'/hub?login_code={code}').status_code == 401


@pytest.mark.parametrize('request_args', [
    {'query_string': {'token': 'ä'}},
    {'headers': {'X-Hub-Token': 'ä'}},
])
def test_non_ascii_tokens_are_refused_without_crashing(client, request_args):
    assert client.get('/hub', **request_args).status_code == 401


def test_non_ascii_bearer_is_refused_without_crashing(client):
    assert client.get('/api/hub/tasks', headers={'Authorization': 'Bearer ä'}).status_code == 401


def test_non_ascii_oauth_state_is_refused_without_crashing(hub, client):
    client.get(f'/hub?token={TOKEN}')
    with client.session_transaction() as session:
        session['oauth_state'] = 'expected-state'
    response = client.post('/api/email/google/callback', json={'code': 'x', 'state': 'ä'})
    assert response.status_code == 403
