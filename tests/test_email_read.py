# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import pytest

ACCOUNT = 'anna@schule.de'
RAW = b'From: Ben <ben@schule.de>\r\nSubject: Referat\r\nDate: Mon, 1 Jun 2026 08:00:00 +0200\r\n\r\nBis morgen!'


class Imap:
    calls = []

    def __init__(self, host, port, ssl_context=None, timeout=None):
        pass

    def login(self, user, password):
        pass

    def select(self, folder, readonly=False):
        Imap.calls.append(('select', folder, readonly))
        return 'OK', [b'1']

    def fetch(self, msg_id, parts):
        Imap.calls.append(('fetch', msg_id, parts))
        return 'OK', [(b'7 (RFC822 {%d}' % len(RAW), RAW), b')']

    def store(self, msg_id, command, flags):
        Imap.calls.append(('store', msg_id, command, flags))
        return 'OK', [b'']

    def logout(self):
        pass


@pytest.fixture
def client(monkeypatch):
    from app import app as hub
    from app import email_service

    Imap.calls = []
    monkeypatch.setattr(email_service.imaplib, 'IMAP4_SSL', Imap)
    monkeypatch.setattr(email_service, 'load_email_config',
                        lambda: {'accounts': [{'email': ACCOUNT, 'provider': 'custom', 'password': 'geheim'}]})
    monkeypatch.setattr(email_service, 'get_provider_settings',
                        lambda provider, address: {'imap_host': 'imap.schule.de', 'imap_port': 993})
    hub.app.config['TESTING'] = True
    with hub.app.test_client() as client:
        client.get(f'/hub?token={hub.API_TOKEN}')
        yield client


def test_opening_a_mail_changes_nothing_on_the_server(client):
    response = client.get(f'/api/email/message/{ACCOUNT}/7')
    assert response.status_code == 200
    assert response.get_json()['email']['subject'] == 'Referat'
    assert ('select', 'INBOX', True) in Imap.calls
    assert not [call for call in Imap.calls if call[0] == 'store']


def test_marking_as_read_needs_a_post(client):
    response = client.post(f'/api/email/message/{ACCOUNT}/7/read', headers={'Origin': 'http://localhost'})
    assert response.status_code == 200
    assert ('store', b'7', '+FLAGS', '\\Seen') in Imap.calls


def test_a_foreign_page_cannot_mark_mail_as_read(client):
    response = client.post(f'/api/email/message/{ACCOUNT}/7/read', headers={'Origin': 'http://evil.example'})
    assert response.status_code == 403
    assert Imap.calls == []


@pytest.mark.parametrize('msg_id', ['7 +FLAGS', '1:*', 'x'])
def test_only_plain_message_numbers_are_marked(client, msg_id):
    assert client.post(f'/api/email/message/{ACCOUNT}/{msg_id}/read').status_code == 400
    assert Imap.calls == []
