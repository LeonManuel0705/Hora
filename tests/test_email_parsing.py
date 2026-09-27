# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import time
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import pytest


@pytest.fixture
def email_service():
    from app import email_service

    return email_service


def html_mail(html):
    msg = MIMEMultipart('alternative')
    msg.attach(MIMEText(html, 'html', 'utf-8'))
    return msg


@pytest.mark.parametrize('header, address', [
    ('Frau Müller <mueller@schule.de>', 'mueller@schule.de'),
    ('"Müller, Anna" <anna.mueller@schule.de>', 'anna.mueller@schule.de'),
    ('mueller@schule.de', 'mueller@schule.de'),
])
def test_sender_address_is_found(email_service, header, address):
    assert email_service.extract_email_address(header) == address


def test_sender_address_is_quick_on_a_hostile_header(email_service):
    start = time.perf_counter()
    email_service.extract_email_address('<' * 200_000)
    assert time.perf_counter() - start < 1


def test_html_body_becomes_text(email_service):
    body = email_service.get_email_body(html_mail('<p>Hallo <b>Welt</b>,</p>\n<p>bis morgen</p>'))
    assert body == 'Hallo Welt, bis morgen'


def test_single_part_html_becomes_text(email_service):
    body = email_service.get_email_body(MIMEText('<p>Hallo <b>Welt</b>,</p>\n<p>bis morgen</p>', 'html', 'utf-8'))
    assert body == 'Hallo Welt, bis morgen'


def test_html_body_is_quick_on_hostile_markup(email_service):
    start = time.perf_counter()
    email_service.get_email_body(html_mail('<' * 3_000_000))
    assert time.perf_counter() - start < 2


def test_punycode_bodies_are_quick(email_service):
    import email

    raw = b'Content-Type: text/plain; charset=punycode\r\n\r\n' + b'a' * 300_000 + b'-' + b'a' * 300_000
    start = time.perf_counter()
    email_service.get_email_body(email.message_from_bytes(raw))
    assert time.perf_counter() - start < 1


def test_long_subjects_are_quick(email_service):
    start = time.perf_counter()
    email_service.decode_email_header('=?a?q?x ' * 20_000)
    assert time.perf_counter() - start < 1


@pytest.mark.parametrize('data, charset, text', [
    ('Grüße'.encode('utf-8'), 'utf-8', 'Grüße'),
    ('Grüße'.encode('latin-1'), 'ISO-8859-1', 'Grüße'),
    (b'hallo', 'zlib', 'hallo'),
    (b'hallo', 'no-such-charset', 'hallo'),
    (b'hallo', 'undefined', 'hallo'),
    (b'hallo', None, 'hallo'),
])
def test_text_is_decoded_with_a_safe_charset(email_service, data, charset, text):
    assert email_service.decode_text(data, charset) == text


def test_encoded_subjects_still_decode(email_service):
    assert email_service.decode_email_header('=?utf-8?q?Gr=C3=BC=C3=9Fe?=') == 'Grüße'
