# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import pytest

BASE = 'https://iserv.schule.de'


class Response:
    def __init__(self, status=200, location=None):
        self.status_code = status
        self.headers = {'Location': location} if location else {}
        self.is_redirect = location is not None and status in (301, 302, 303, 307, 308)
        self.closed = False

    def close(self):
        self.closed = True


class Session:
    def __init__(self, routes):
        self.routes = routes
        self.requested = []

    def request(self, method, url, allow_redirects=True, **kwargs):
        assert allow_redirects is False
        self.requested.append((method, url))
        return self.routes.get(url, Response(404))


@pytest.fixture
def request_on_host():
    from app.iserv_service import _request_on_host

    return _request_on_host


def test_redirects_within_iserv_are_followed(request_on_host):
    session = Session({
        f'{BASE}/iserv/infodisplay/show/3': Response(302, '/iserv/infodisplay/file/3/1'),
        f'{BASE}/iserv/infodisplay/file/3/1': Response(200),
    })
    response = request_on_host(session, 'GET', f'{BASE}/iserv/infodisplay/show/3', BASE, timeout=1)
    assert response.status_code == 200
    assert [url for _, url in session.requested] == [f'{BASE}/iserv/infodisplay/show/3', f'{BASE}/iserv/infodisplay/file/3/1']


@pytest.mark.parametrize('location', [
    'http://169.254.169.254/latest/meta-data/',
    'https://evil.example/plan.pdf',
    'https://iserv.schule.de.evil.example/plan.pdf',
    'https://user@evil.example/plan.pdf',
    'file:///etc/passwd',
    'http://[',
    'http://evil.example:6379\\@iserv.schule.de/plan.pdf',
    'https://evil.example\\.iserv.schule.de/plan.pdf',
])
def test_redirects_off_the_iserv_host_are_never_requested(request_on_host, location):
    session = Session({f'{BASE}/iserv/infodisplay/file/3/1': Response(302, location)})
    assert request_on_host(session, 'HEAD', f'{BASE}/iserv/infodisplay/file/3/1', BASE, timeout=1) is None
    assert session.requested == [('HEAD', f'{BASE}/iserv/infodisplay/file/3/1')]


def test_foreign_start_url_is_never_requested(request_on_host):
    session = Session({})
    assert request_on_host(session, 'GET', 'https://evil.example/x.pdf', BASE) is None
    assert session.requested == []


def test_redirect_loops_end(request_on_host):
    session = Session({f'{BASE}/a': Response(302, '/a')})
    assert request_on_host(session, 'GET', f'{BASE}/a', BASE) is None
    assert len(session.requested) == 6


def test_scraped_links_keep_only_the_iserv_host():
    from app.iserv_service import _same_host_only

    links = [
        f'{BASE}/iserv/infodisplay/file/3/1',
        'https://ISERV.schule.de/iserv/public/plan.png',
        'http://evil.example:6379\\@iserv.schule.de/plan.pdf',
        'https://evil.example/plan.pdf',
        '/iserv/relative.pdf',
    ]
    assert _same_host_only(links, BASE) == links[:2]


def test_international_iserv_hosts_still_match(request_on_host):
    base = 'https://iserv.schule-münchen.de'
    session = Session({
        f'{base}/a': Response(302, f'{base}/b'),
        f'{base}/b': Response(200),
    })
    assert request_on_host(session, 'GET', f'{base}/a', base).status_code == 200


def test_connect_refuses_a_backslash_in_the_iserv_address():
    from app.iserv_service import IServService

    result = IServService().connect('anna', 'geheim', 'evil.example\\.iserv.schule.de')
    assert result == {'success': False, 'error': 'Ungültige IServ-Adresse'}


@pytest.mark.parametrize('location, followed', [
    ('https://iserv.schule.de:443/iserv/b', True),
    ('http://iserv.schule.de/iserv/b', False),
    ('https://iserv.schule.de:6379/iserv/b', False),
])
def test_redirects_keep_scheme_and_port(request_on_host, location, followed):
    session = Session({f'{BASE}/a': Response(302, location), location: Response(200)})
    response = request_on_host(session, 'GET', f'{BASE}/a', BASE)
    assert (response is not None) == followed
    assert (('GET', location) in session.requested) == followed
