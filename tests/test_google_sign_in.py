# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import pytest

from app import google_oauth

CALENDAR = google_oauth.CALENDAR_SCOPE
GMAIL_READ = google_oauth.GMAIL_READ_SCOPE


@pytest.fixture
def hub(monkeypatch):
    from app import app as hub

    monkeypatch.setattr(hub, 'DESKTOP_TOKEN', None)
    monkeypatch.setattr(hub, '_google_states', {})
    hub.app.config['TESTING'] = True
    return hub


@pytest.fixture
def app_window(hub):
    with hub.app.test_client() as client:
        client.get(f'/hub?token={hub.API_TOKEN}')
        yield client


@pytest.fixture
def browser(hub):
    return hub.app.test_client()


@pytest.fixture
def google(monkeypatch):
    calls = []
    states = iter(f'state-{n}' for n in range(1, 100))

    def start():
        state = next(states)
        return {'success': True, 'auth_url': f'https://accounts.google.com/o/oauth2/auth?state={state}', 'state': state}

    def complete(code):
        calls.append(code)
        return {'success': True, 'email': 'lea@example.com'}

    monkeypatch.setattr(google_oauth, 'start_oauth_flow', start)
    monkeypatch.setattr(google_oauth, 'complete_oauth_flow', complete)
    return calls


def start(app_window):
    return app_window.post('/api/email/google/auth').get_json()['state']


def progress(app_window, state):
    return app_window.get(f'/api/email/google/progress?state={state}').get_json()


def test_sign_in_started_in_the_app_finishes_in_a_browser_without_its_cookies(app_window, browser, google):
    state = start(app_window)
    assert progress(app_window, state)['done'] is False
    page = browser.get(f'/api/email/google/oauth-callback?state={state}&code=abc')
    assert page.status_code == 200
    html = page.get_data(as_text=True)
    assert 'Google ist verbunden' in html and 'lea@example.com' in html
    assert google == ['abc']
    assert progress(app_window, state) == {'success': True, 'done': True, 'ok': True, 'email': 'lea@example.com', 'error': ''}


def test_a_state_works_only_once(app_window, browser, google):
    state = start(app_window)
    browser.get(f'/api/email/google/oauth-callback?state={state}&code=abc')
    replay = browser.get(f'/api/email/google/oauth-callback?state={state}&code=evil')
    assert replay.status_code == 400 and 'Anmeldung abgelaufen' in replay.get_data(as_text=True)
    assert google == ['abc']


def test_unknown_and_expired_states_are_refused(hub, app_window, browser, google, monkeypatch):
    unknown = browser.get('/api/email/google/oauth-callback?state=erfunden&code=abc')
    assert unknown.status_code == 400 and 'Anmeldung abgelaufen' in unknown.get_data(as_text=True)
    monkeypatch.setattr(hub, 'GOOGLE_STATE_TTL', -1)
    state = start(app_window)
    expired = browser.get(f'/api/email/google/oauth-callback?state={state}&code=abc')
    assert expired.status_code == 400
    assert google == []
    assert progress(app_window, state)['ok'] is False


def test_a_cancelled_sign_in_reaches_the_app_and_is_escaped(app_window, browser, google):
    state = start(app_window)
    page = browser.get(f'/api/email/google/oauth-callback?state={state}&error=<script>alert(1)</script>')
    html = page.get_data(as_text=True)
    assert 'Anmeldung abgebrochen' in html and '<script>alert(1)' not in html
    result = progress(app_window, state)
    assert result['done'] is True and result['ok'] is False and 'abgebrochen' in result['error']
    assert google == []


def test_progress_needs_the_hub_login(app_window, browser, google):
    state = start(app_window)
    assert browser.get(f'/api/email/google/progress?state={state}').status_code == 401


class FakeCredentials:
    def __init__(self, granted):
        self.granted_scopes = granted
        self.token = 'access'
        self.refresh_token = 'refresh'
        self.token_uri = 'https://oauth2.googleapis.com/token'
        self.client_id = 'client'
        self.client_secret = 'secret'


class FakeFlow:
    def __init__(self, granted):
        self.credentials = FakeCredentials(granted)

    def fetch_token(self, **kwargs):
        pass


class Call:
    def __init__(self, value):
        self.value = value

    def execute(self):
        return self.value


class FakeService:
    def __init__(self, api):
        self.api = api

    def users(self):
        return self

    def getProfile(self, userId):
        return Call({'emailAddress': 'mail@example.com'})

    def calendars(self):
        return self

    def get(self, calendarId):
        return Call({'id': 'kalender@example.com'})


@pytest.fixture
def token_store(monkeypatch):
    saved = {}
    monkeypatch.setattr(google_oauth, '_get_oauth_client_config', lambda: {'web': {}})
    monkeypatch.setattr(google_oauth, 'build', lambda api, version, credentials: FakeService(api))
    monkeypatch.setattr(google_oauth, 'load_tokens', lambda: dict(saved))
    monkeypatch.setattr(google_oauth, 'save_tokens', lambda tokens: saved.update(tokens) or True)
    return saved


def grant(monkeypatch, scopes):
    monkeypatch.setattr(google_oauth.Flow, 'from_client_config', classmethod(lambda cls, *args, **kwargs: FakeFlow(scopes)))


def test_calendar_alone_is_enough_and_its_scopes_are_kept(monkeypatch, token_store):
    grant(monkeypatch, [CALENDAR])
    result = google_oauth.complete_oauth_flow('abc')
    assert result['success'] is True and result['email'] == 'kalender@example.com'
    assert token_store['kalender@example.com']['scopes'] == [CALENDAR]
    creds = google_oauth.get_credentials('kalender@example.com')
    assert list(creds.scopes) == [CALENDAR]


def test_gmail_gives_the_address_when_it_was_granted(monkeypatch, token_store):
    grant(monkeypatch, [GMAIL_READ, CALENDAR])
    assert google_oauth.complete_oauth_flow('abc')['email'] == 'mail@example.com'


def test_a_blocked_gmail_falls_back_to_the_calendar(monkeypatch, token_store):
    grant(monkeypatch, [GMAIL_READ, CALENDAR])

    def blocked(self, userId):
        raise RuntimeError('Gmail API has not been used in this project')

    monkeypatch.setattr(FakeService, 'getProfile', blocked)
    assert google_oauth.complete_oauth_flow('abc')['email'] == 'kalender@example.com'


def test_sign_in_without_the_calendar_asks_for_it(monkeypatch, token_store):
    grant(monkeypatch, [GMAIL_READ])
    result = google_oauth.complete_oauth_flow('abc')
    assert result['success'] is False and 'Kalender' in result['error']
    assert token_store == {}


def test_oauthlib_accepts_a_smaller_grant():
    import os

    assert os.environ.get('OAUTHLIB_RELAX_TOKEN_SCOPE')
