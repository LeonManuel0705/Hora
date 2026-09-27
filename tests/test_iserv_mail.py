# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import pytest

PLAIN_MAIL = (
    "From: Frau Mueller <mueller@schule.de>\r\n"
    "To: leon@iserv\r\n"
    "Subject: =?utf-8?q?Klausur_n=C3=A4chste_Woche?=\r\n"
    "Date: Thu, 25 Sep 2026 08:15:00 +0200\r\n"
    "Content-Type: text/plain; charset=utf-8\r\n"
    "\r\n"
    "Bitte bringt einen Taschenrechner mit.\r\n"
)

HTML_MAIL = (
    "From: sekretariat@schule.de\r\n"
    "Subject: Info\r\n"
    "Date: Fri, 26 Sep 2026 10:00:00 +0200\r\n"
    "Content-Type: text/html; charset=utf-8\r\n"
    "\r\n"
    "<p>Hallo <b>alle</b></p><img src=x onerror=alert(1)>\r\n"
)


class FakeApi:
    def __init__(self, source='', listing=None):
        self.source = source
        self.listing = listing
        self.calls = []

    def get_email_source(self, uid, path='INBOX'):
        self.calls.append(('source', uid, path))
        return self.source

    def get_emails(self, path='INBOX', length=50):
        self.calls.append(('list', path, length))
        return self.listing


@pytest.fixture
def service():
    from app.iserv_service import IServService

    item = IServService()
    item.connected = True
    return item


def test_detail_reads_the_mail_source(service):
    service.api = FakeApi(PLAIN_MAIL)
    result = service.get_email_detail('42')
    assert result['success'] is True
    mail = result['email']
    assert mail['id'] == '42'
    assert mail['from'] == 'mueller@schule.de'
    assert mail['from_name'] == 'Frau Mueller'
    assert mail['subject'] == 'Klausur nächste Woche'
    assert mail['date'] == '2026-09-25 08:15'
    assert 'Taschenrechner' in mail['body']
    assert service.api.calls == [('source', '42', 'INBOX')]


def test_detail_hands_out_html_only_as_text(service):
    service.api = FakeApi(HTML_MAIL)
    mail = service.get_email_detail('7')['email']
    assert 'html' not in mail
    assert '<' not in mail['body']
    assert 'Hallo alle' in mail['body']


@pytest.mark.parametrize('msg_id', ['1&path=Trash', '../1', '', 'abc'])
def test_detail_refuses_odd_ids(service, msg_id):
    service.api = FakeApi(PLAIN_MAIL)
    assert service.get_email_detail(msg_id)['success'] is False
    assert service.api.calls == []


def test_detail_quotes_the_folder(service):
    service.api = FakeApi(PLAIN_MAIL)
    service.get_email_detail('7', folder='INBOX&msg=1')
    assert service.api.calls == [('source', '7', 'INBOX%26msg%3D1')]


def test_a_page_without_mail_headers_is_not_a_mail(service):
    service.api = FakeApi('<html><body>Anmelden</body></html>')
    assert service.get_email_detail('7')['success'] is False


def test_detail_needs_a_connection(service):
    service.connected = False
    service.api = FakeApi(PLAIN_MAIL)
    assert service.get_email_detail('7')['success'] is False
    assert service.api.calls == []


def test_list_reads_a_wrapped_payload(service):
    service.api = FakeApi(listing={
        'recordsTotal': 1,
        'data': [{
            'uid': 5,
            'subject': 'Elternabend',
            'from': [{'name': 'Frau Mueller', 'email': 'mueller@schule.de'}],
            'date': {'date': '2026-09-25 08:15:00.000000', 'timezone': 'Europe/Berlin'},
            'flags': {'seen': False},
        }],
    })
    result = service.get_emails(limit=10)
    assert result == {'success': True, 'emails': [{
        'uid': 5,
        'from': 'mueller@schule.de',
        'from_name': 'Frau Mueller',
        'subject': 'Elternabend',
        'date': '2026-09-25 08:15:00.000000',
        'preview': '',
        'read': False,
    }]}


def test_list_reads_a_plain_list(service):
    service.api = FakeApi(listing=[
        {'uid': 6, 'from': 'sekretariat@schule.de', 'subject': 'Info', 'unseen': True},
        'kaputt',
    ])
    emails = service.get_emails()['emails']
    assert len(emails) == 1
    assert emails[0]['from'] == 'sekretariat@schule.de'
    assert emails[0]['from_name'] == 'sekretariat'
    assert emails[0]['read'] is False


def test_list_quotes_the_folder(service):
    service.api = FakeApi(listing=[])
    service.get_emails(folder='INBOX&length=100000', limit=3)
    assert service.api.calls == [('list', 'INBOX%26length%3D100000', 3)]
