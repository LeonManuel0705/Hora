# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import hashlib
import io
import json
import os
import stat
import sys
import tarfile
import textwrap
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from app import local_ai

POSIX = sys.platform != 'win32'


class Payloads:
    def __init__(self):
        self.files = {}
        self.honour_range = True
        self.fail_after = None
        self.requests = []


def serve(payloads):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            payloads.requests.append((self.path, self.headers.get('Range')))
            if self.path.startswith('/redirect/'):
                self.send_response(302)
                self.send_header('Location', '/' + self.path.split('/', 2)[2])
                self.end_headers()
                return
            body = payloads.files.get(self.path.lstrip('/'))
            if body is None:
                self.send_response(404)
                self.end_headers()
                return
            start = 0
            header = self.headers.get('Range')
            if header and payloads.honour_range:
                start = int(header.split('=')[1].split('-')[0])
                if start >= len(body):
                    self.send_response(416)
                    self.end_headers()
                    return
                self.send_response(206)
                self.send_header('Content-Range', f'bytes {start}-{len(body) - 1}/{len(body)}')
            else:
                self.send_response(200)
            chunk = body[start:]
            self.send_header('Content-Length', str(len(chunk)))
            self.end_headers()
            if payloads.fail_after is not None:
                cut, payloads.fail_after = payloads.fail_after, None
                self.wfile.write(chunk[:cut])
                self.wfile.flush()
                self.connection.shutdown(2)
                return
            self.wfile.write(chunk)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


@pytest.fixture
def http():
    payloads = Payloads()
    server = serve(payloads)
    payloads.base = f'http://127.0.0.1:{server.server_address[1]}'
    yield payloads
    server.shutdown()
    server.server_close()


@pytest.fixture
def isolated(tmp_path, monkeypatch):
    runtime_root = tmp_path / 'runtime'
    runtime_dir = runtime_root / local_ai.RUNTIME_TAG
    monkeypatch.setattr(local_ai, 'MODELS_DIR', tmp_path / 'models')
    monkeypatch.setattr(local_ai, 'RUNTIME_ROOT', runtime_root)
    monkeypatch.setattr(local_ai, 'RUNTIME_DIR', runtime_dir)
    monkeypatch.setattr(local_ai, 'RUNTIME_MARKER', runtime_dir / '.installed.json')
    monkeypatch.setattr(local_ai, 'PID_FILE', runtime_root / 'server.json')
    monkeypatch.setattr(local_ai, 'LOG_FILE', runtime_root / 'server.log')
    monkeypatch.setattr(local_ai, 'CPU_ONLY_FILE', runtime_root / 'cpu-only')
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: False)
    monkeypatch.setattr(local_ai, 'free_space', lambda: 10 ** 12)
    monkeypatch.setattr(local_ai, 'DOWNLOAD_ATTEMPTS', 3)
    monkeypatch.setattr(local_ai.Installer, '_wait_before_retry', lambda self, failures: None)
    return tmp_path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def use_model(monkeypatch, http, body, name='tiny.gguf'):
    http.files[name] = body
    monkeypatch.setattr(local_ai, 'MODEL', {'name': 'Tiny', 'file': name, 'size': len(body), 'sha256': sha(body),
                                            'url': f'{http.base}/{name}'})


class FakeServer:
    def __init__(self):
        self.started = 0
        self.stopped = 0

    def ensure(self, cancel=None):
        self.started += 1
        return 'http://127.0.0.1:1', 'key'

    def stop(self):
        self.stopped += 1

    def state(self):
        return 'stopped'


def fake_runtime_archive():
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as bundle:
        def add(name, data, mode=0o755):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = mode
            bundle.addfile(info, io.BytesIO(data))

        top = tarfile.TarInfo('llama-b1/')
        top.type = tarfile.DIRTYPE
        bundle.addfile(top)
        add('llama-b1/llama-server', b'#!/bin/sh\necho "version: test"\n')
        add('llama-b1/libllama.0.5.0.dylib', b'lib', 0o755)
        link = tarfile.TarInfo('llama-b1/libllama.dylib')
        link.type = tarfile.SYMTYPE
        link.linkname = 'libllama.0.5.0.dylib'
        bundle.addfile(link)
        add('llama-b1/llama-bench', b'not needed')
        add('llama-b1/LICENSE', b'MIT', 0o644)
    return buffer.getvalue()


def run_install(installer, timeout=20):
    assert installer.start()
    installer.wait(timeout)
    return installer.job()


@pytest.mark.skipif(not POSIX, reason='the fake runtime is a shell script')
def test_install_downloads_unpacks_and_starts(isolated, http, monkeypatch):
    archive = fake_runtime_archive()
    http.files['runtime.tar.gz'] = archive
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: ('runtime.tar.gz', len(archive), sha(archive)))
    monkeypatch.setattr(local_ai, 'RUNTIME_URL', http.base + '/{file}')
    use_model(monkeypatch, http, os.urandom(300_000))
    fake = FakeServer()
    monkeypatch.setattr(local_ai, 'server', fake)

    job = run_install(local_ai.Installer())

    assert job['state'] == 'done', job
    assert job['steps'] == ['runtime', 'model', 'verify', 'start']
    assert fake.started == 1
    assert (local_ai.RUNTIME_DIR / 'llama-server').stat().st_mode & stat.S_IXUSR
    assert os.readlink(local_ai.RUNTIME_DIR / 'libllama.dylib') == 'libllama.0.5.0.dylib'
    assert not (local_ai.RUNTIME_DIR / 'llama-bench').exists()
    assert local_ai.model_path() == local_ai.MODELS_DIR / 'tiny.gguf'
    assert not list(local_ai.MODELS_DIR.glob('*.part'))
    assert local_ai.is_installed()


def test_model_download_resumes_where_it_stopped(isolated, http, monkeypatch):
    body = os.urandom(400_000)
    use_model(monkeypatch, http, body)
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / 'tiny.gguf.part').write_bytes(body[:150_000])

    job = run_install(local_ai.Installer())

    assert job['state'] == 'done', job
    assert (local_ai.MODELS_DIR / 'tiny.gguf').read_bytes() == body
    assert http.requests[-1][1] == 'bytes=150000-'
    assert job['steps'] == ['model', 'verify']


def test_interrupted_transfer_continues_with_a_range_request(isolated, http, monkeypatch):
    body = os.urandom(500_000)
    use_model(monkeypatch, http, body)
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    monkeypatch.setattr(local_ai, 'CHUNK', 16_384)
    http.fail_after = 120_000

    job = run_install(local_ai.Installer())

    assert job['state'] == 'done', job
    assert (local_ai.MODELS_DIR / 'tiny.gguf').read_bytes() == body
    ranges = [header for _, header in http.requests]
    assert ranges[0] is None and ranges[-1] and ranges[-1].startswith('bytes=')


def test_server_without_range_support_restarts_cleanly(isolated, http, monkeypatch):
    body = os.urandom(200_000)
    use_model(monkeypatch, http, body)
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    http.honour_range = False
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / 'tiny.gguf.part').write_bytes(body[:50_000])

    job = run_install(local_ai.Installer())

    assert job['state'] == 'done', job
    assert (local_ai.MODELS_DIR / 'tiny.gguf').read_bytes() == body


def test_redirects_are_followed(isolated, http, monkeypatch):
    body = os.urandom(10_000)
    use_model(monkeypatch, http, body)
    local_ai.MODEL['url'] = f'{http.base}/redirect/tiny.gguf'
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)

    assert run_install(local_ai.Installer())['state'] == 'done'


def test_corrupt_download_is_retried_once_then_reported(isolated, http, monkeypatch):
    body = os.urandom(50_000)
    use_model(monkeypatch, http, body)
    local_ai.MODEL['sha256'] = '0' * 64
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)

    job = run_install(local_ai.Installer())

    assert job['state'] == 'error' and job['error']['code'] == 'checksum'
    assert len([path for path, _ in http.requests if path == '/tiny.gguf']) == 2
    assert local_ai.model_path() is None
    assert not (local_ai.MODELS_DIR / 'tiny.gguf.part').exists()


def test_missing_file_is_an_http_error(isolated, http, monkeypatch):
    use_model(monkeypatch, http, b'x' * 100)
    local_ai.MODEL['url'] = f'{http.base}/gone.gguf'
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)

    job = run_install(local_ai.Installer())

    assert job['state'] == 'error' and job['error'] == {'code': 'http', 'status': 404}


def test_unreachable_server_reports_offline_and_keeps_nothing_broken(isolated, monkeypatch):
    monkeypatch.setattr(local_ai, 'MODEL', {'name': 'Tiny', 'file': 'tiny.gguf', 'size': 10, 'sha256': '0' * 64,
                                            'url': 'http://127.0.0.1:9/tiny.gguf'})
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)

    job = run_install(local_ai.Installer(), timeout=60)

    assert job['state'] == 'error' and job['error']['code'] == 'offline'


def test_cancel_keeps_the_partial_file(isolated, http, monkeypatch):
    body = os.urandom(2_000_000)
    use_model(monkeypatch, http, body)
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    monkeypatch.setattr(local_ai, 'CHUNK', 16_384)
    installer = local_ai.Installer()
    original = installer._advance

    def slow(phase_done, delta):
        original(phase_done, delta)
        if phase_done > 100_000:
            installer.cancel()

    installer._advance = slow
    job = run_install(installer)

    assert job['state'] == 'cancelled'
    partial = local_ai.MODELS_DIR / 'tiny.gguf.part'
    assert 100_000 < partial.stat().st_size < len(body)
    assert local_ai.status()['model']['partial'] == partial.stat().st_size


def test_not_enough_disk_space_is_reported_before_downloading(isolated, http, monkeypatch):
    use_model(monkeypatch, http, os.urandom(1000))
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    monkeypatch.setattr(local_ai, 'free_space', lambda: 1000)

    job = run_install(local_ai.Installer())

    assert job['state'] == 'error' and job['error']['code'] == 'disk_full'
    assert job['error']['missing'] >= local_ai.DISK_MARGIN
    assert http.requests == []


def test_unknown_platform_is_unsupported(isolated, monkeypatch):
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)

    job = run_install(local_ai.Installer())

    assert job['state'] == 'error' and job['error']['code'] == 'unsupported'
    assert local_ai.status()['supported'] is False


def test_a_second_start_while_running_is_ignored(isolated, http, monkeypatch):
    use_model(monkeypatch, http, os.urandom(1_000_000))
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: None)
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    monkeypatch.setattr(local_ai, 'CHUNK', 8192)
    installer = local_ai.Installer()
    gate = threading.Event()
    original = installer._advance

    def held(phase_done, delta):
        original(phase_done, delta)
        gate.wait(5)

    installer._advance = held
    assert installer.start()
    assert not installer.start()
    gate.set()
    installer.wait(20)
    assert installer.job()['state'] == 'done'


def tar_with(entries):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as bundle:
        for name, kind, value in entries:
            info = tarfile.TarInfo(name)
            if kind == 'file':
                info.size = len(value)
                bundle.addfile(info, io.BytesIO(value))
            elif kind == 'link':
                info.type = tarfile.SYMTYPE
                info.linkname = value
                bundle.addfile(info)
            elif kind == 'hard':
                info.type = tarfile.LNKTYPE
                info.linkname = value
                bundle.addfile(info)
    return buffer.getvalue()


@pytest.mark.parametrize('entries', [
    [('../evil.so', 'file', b'x')],
    [('/etc/evil.so', 'file', b'x')],
    [('top/../../evil.so', 'file', b'x')],
    [('top/libx.so', 'link', '/etc/passwd')],
    [('top/libx.so', 'link', '../outside.so')],
    [('top/libx.so', 'hard', 'top/liby.so'), ('top/liby.so', 'file', b'y')],
    [('top/libx.so', 'link', 'missing.so'), ('top/llama-server', 'file', b'x')],
])
def test_unsafe_tar_archives_are_refused(tmp_path, entries):
    archive = tmp_path / 'bad.tar.gz'
    archive.write_bytes(tar_with(entries))
    with pytest.raises(local_ai.InstallError) as refused:
        local_ai.unpack(archive, tmp_path / 'out')
    assert refused.value.code == 'runtime_broken'
    assert not (tmp_path / 'evil.so').exists() and not (tmp_path / 'outside.so').exists()


@pytest.mark.parametrize('name', ['../evil.dll', 'C:/evil.dll', 'a\\..\\..\\evil.dll', '/abs.dll'])
def test_unsafe_zip_archives_are_refused(tmp_path, name):
    archive = tmp_path / 'bad.zip'
    with zipfile.ZipFile(archive, 'w') as bundle:
        bundle.writestr(name, b'x')
    with pytest.raises(local_ai.InstallError):
        local_ai.unpack(archive, tmp_path / 'out')
    assert not (tmp_path / 'evil.dll').exists()


def test_flat_zip_keeps_only_the_server_and_its_libraries(tmp_path):
    archive = tmp_path / 'runtime.zip'
    with zipfile.ZipFile(archive, 'w') as bundle:
        for name in ('llama-server.exe', 'ggml-cpu-haswell.dll', 'llama.dll', 'llama-bench.exe', 'LICENSE-LLVM-OpenMP'):
            bundle.writestr(name, name.encode())
    local_ai.unpack(archive, tmp_path / 'out')
    assert sorted(path.name for path in (tmp_path / 'out').iterdir()) == [
        'LICENSE-LLVM-OpenMP', 'ggml-cpu-haswell.dll', 'llama-server.exe', 'llama.dll']


FAKE_SERVER = textwrap.dedent('''
    import json, os, sys
    from http.server import BaseHTTPRequestHandler, HTTPServer

    args = sys.argv[1:]
    if args == ['--version']:
        print('version: fake')
        sys.exit(0)
    port = int(args[args.index('--port') + 1])
    if os.environ.get('FAKE_GPU_CRASH') and '--device' not in args:
        print('ggml_vulkan: device lost', file=sys.stderr)
        sys.exit(134)
    with open(os.path.join(os.path.dirname(sys.argv[0]), 'argv.json'), 'w') as record:
        json.dump(args, record)
    model = args[args.index('-m') + 1]
    key = os.environ['LLAMA_API_KEY']
    assert os.path.isfile(model), model
    assert '127.0.0.1' == args[args.index('--host') + 1]

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            self.send_response(200 if self.path == '/health' else 404)
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')

        def do_POST(self):
            if self.headers.get('Authorization') != 'Bearer ' + key:
                self.send_response(401)
                self.end_headers()
                return
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            text = 'Echo: ' + body['messages'][-1]['content']
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.end_headers()
            for word in text.split(' '):
                chunk = {'choices': [{'delta': {'content': word + ' '}}]}
                self.wfile.write(('data: ' + json.dumps(chunk) + '\\n\\n').encode())
            self.wfile.write(b'data: [DONE]\\n\\n')

    HTTPServer(('127.0.0.1', port), Handler).serve_forever()
''')


@pytest.fixture
def fake_runtime(isolated):
    local_ai.RUNTIME_DIR.mkdir(parents=True)
    script = local_ai.RUNTIME_DIR / 'fake_server.py'
    script.write_text(FAKE_SERVER)
    exe = local_ai.RUNTIME_DIR / local_ai.SERVER_NAME
    exe.write_text(f'#!{sys.executable}\nimport runpy, sys\nrunpy.run_path({str(script)!r}, run_name="__main__")\n')
    exe.chmod(0o755)
    local_ai.RUNTIME_MARKER.write_text('{}')
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / local_ai.MODEL['file']).write_bytes(b'gguf')
    server = local_ai.Server()
    yield server
    server.stop()


@pytest.mark.skipif(not POSIX, reason='the fake runtime is a script with a shebang')
def test_server_starts_on_loopback_with_a_key_and_streams(fake_runtime):
    server = fake_runtime
    assert server.state() == 'stopped'
    text = ''.join(server.stream([{'role': 'user', 'content': 'Hallo Welt'}]))
    assert text.strip() == 'Echo: Hallo Welt'
    assert server.state() == 'ready'
    record = json.loads(local_ai.PID_FILE.read_text())
    assert record['exe'] == str(local_ai.RUNTIME_DIR / local_ai.SERVER_NAME)
    server.stop()
    assert server.state() == 'stopped'
    assert not local_ai.PID_FILE.exists()


@pytest.mark.skipif(not POSIX, reason='the fake runtime is a script with a shebang')
def test_a_crashed_server_is_restarted_on_the_next_question(fake_runtime):
    server = fake_runtime
    server.chat([{'role': 'user', 'content': 'eins'}])
    server._proc.kill()
    server._proc.wait(5)
    assert server.chat([{'role': 'user', 'content': 'zwei'}]).strip() == 'Echo: zwei'


@pytest.mark.skipif(not POSIX, reason='the fake runtime is a script with a shebang')
def test_leftover_server_from_an_earlier_run_is_stopped(fake_runtime):
    first = fake_runtime
    first.chat([{'role': 'user', 'content': 'hi'}])
    orphan = first._proc
    first._proc = None
    record = local_ai.PID_FILE.read_text()
    second = local_ai.Server()
    try:
        local_ai.PID_FILE.write_text(record)
        second.chat([{'role': 'user', 'content': 'hi'}])
        orphan.wait(5)
        assert orphan.returncode is not None
    finally:
        second.stop()
        if orphan.poll() is None:
            orphan.kill()


@pytest.mark.skipif(not POSIX, reason='the fake runtime is a script with a shebang')
def test_the_key_never_appears_on_the_command_line(fake_runtime):
    fake_runtime.chat([{'role': 'user', 'content': 'hi'}])
    args = json.loads((local_ai.RUNTIME_DIR / 'argv.json').read_text())
    assert fake_runtime._key not in ' '.join(args)
    assert '--no-slots' in args and args[args.index('--host') + 1] == '127.0.0.1'


@pytest.mark.skipif(not POSIX, reason='the fake runtime is a script with a shebang')
def test_a_gpu_crash_falls_back_to_the_cpu_and_remembers_it(fake_runtime, monkeypatch):
    monkeypatch.setenv('FAKE_GPU_CRASH', '1')
    assert fake_runtime.chat([{'role': 'user', 'content': 'eins'}]).strip() == 'Echo: eins'
    assert local_ai.CPU_ONLY_FILE.exists()
    fake_runtime.stop()
    assert fake_runtime.chat([{'role': 'user', 'content': 'zwei'}]).strip() == 'Echo: zwei'
    args = json.loads((local_ai.RUNTIME_DIR / 'argv.json').read_text())
    assert args[args.index('--device') + 1] == 'none'


def test_a_runtime_that_cannot_be_executed_does_not_hang_in_starting(isolated):
    local_ai.RUNTIME_DIR.mkdir(parents=True)
    (local_ai.RUNTIME_DIR / local_ai.SERVER_NAME).write_bytes(b'not a program')
    local_ai.RUNTIME_MARKER.write_text('{}')
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / local_ai.MODEL['file']).write_bytes(b'gguf')
    server = local_ai.Server()
    with pytest.raises(local_ai.ServerError) as failed:
        server.ensure()
    assert failed.value.reason in ('spawn_failed', 'exited')
    assert server.state() == 'stopped'


def test_unrelated_process_with_the_recorded_pid_is_left_alone(isolated, monkeypatch):
    local_ai.RUNTIME_ROOT.mkdir(parents=True)
    local_ai.PID_FILE.write_text(json.dumps({'pid': os.getpid(), 'exe': '/nowhere/llama-server'}))
    killed = []
    monkeypatch.setattr(local_ai, '_kill', killed.append)
    assert local_ai.reap_stale_server() is False
    assert killed == []
    assert not local_ai.PID_FILE.exists()


def test_start_failure_reports_the_log(isolated, monkeypatch):
    if not POSIX:
        pytest.skip('shell script runtime')
    local_ai.RUNTIME_DIR.mkdir(parents=True)
    exe = local_ai.RUNTIME_DIR / local_ai.SERVER_NAME
    exe.write_text('#!/bin/sh\necho "failed to allocate buffer" >&2\nexit 3\n')
    exe.chmod(0o755)
    local_ai.RUNTIME_MARKER.write_text('{}')
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / local_ai.MODEL['file']).write_bytes(b'gguf')
    server = local_ai.Server()
    with pytest.raises(local_ai.ServerError) as failed:
        server.ensure()
    assert failed.value.reason == 'exited'
    assert 'failed to allocate buffer' in failed.value.log_tail
    assert server.state() == 'stopped'


def test_status_reports_sizes_and_install_state(isolated, monkeypatch):
    monkeypatch.setattr(local_ai, 'runtime_spec', lambda: ('r.tar.gz', 1000, 'x'))
    status = local_ai.status()
    assert status['installed'] is False and status['supported'] is True
    assert status['runtime'] == {'installed': False, 'kind': None, 'download': 1000}
    assert status['model']['download'] == local_ai.MODEL['size']
    assert status['needed'] == 1000 + local_ai.RUNTIME_UNPACKED + local_ai.MODEL['size']
    assert status['job']['state'] == 'idle'


def test_existing_python_runtime_and_model_count_as_installed(isolated, monkeypatch):
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / 'gemma-4-E2B-it-Q4_K_M.gguf').write_bytes(b'gguf')
    assert local_ai.is_installed()
    assert local_ai.runtime_kind() == 'python'
    assert local_ai.status()['model']['name'] == 'Gemma 4 E2B'


def test_uninstall_removes_model_and_runtime(isolated):
    local_ai.RUNTIME_DIR.mkdir(parents=True)
    (local_ai.RUNTIME_DIR / local_ai.SERVER_NAME).write_bytes(b'x')
    local_ai.RUNTIME_MARKER.write_text('{}')
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / 'model.gguf').write_bytes(b'x')
    (local_ai.MODELS_DIR / 'other.gguf.part').write_bytes(b'x')
    assert local_ai.uninstall()
    assert not local_ai.MODELS_DIR.exists() and not local_ai.RUNTIME_ROOT.exists()
    assert not local_ai.is_installed()


@pytest.fixture
def hub(isolated, tmp_path, monkeypatch):
    from app import app as hub_module
    from app import assistant_service as ai
    from app import database as db
    from app import ui_data

    monkeypatch.setattr(db, 'DATABASE_PATH', str(tmp_path / 'hub.db'))
    db.init_db()
    monkeypatch.setattr(ui_data, 'refresh_weather_soon', lambda location: None)
    monkeypatch.setattr(ai, 'check_ollama_status', lambda: {'available': False, 'models': []})
    monkeypatch.setattr(ai, 'check_claude_status', lambda: {'available': False, 'reason': 'no_key'})
    monkeypatch.setattr(local_ai, 'installer', local_ai.Installer())
    monkeypatch.setattr(local_ai, 'server', FakeServer())
    hub_module.app.config['TESTING'] = True
    with hub_module.app.test_client() as client:
        client.get(f'/hub?token={hub_module.API_TOKEN}')
        yield client


def test_first_visit_shows_the_install_page(hub):
    page = hub.get('/hub/assistant').get_data(as_text=True)
    assert 'data-page-module="assistant"' in page
    assert 'id="aiInstall"' in page
    assert 'aria-current="page"' in page.split('id="navDrawer"')[1].split('</div>')[0]


def test_a_running_ollama_alone_does_not_skip_the_install(hub, monkeypatch):
    from app import assistant_service as ai

    monkeypatch.setattr(ai, 'check_ollama_status', lambda: {'available': True, 'models': ['gemma2:2b']})
    assert 'id="aiInstall"' in hub.get('/hub/assistant').get_data(as_text=True)


@pytest.mark.parametrize('config', [
    {'preferred_backend': 'ollama'},
    {'preferred_backend': 'offline'},
    {'preferred_backend': 'auto', 'claude_api_key': 'sk-test'},
])
def test_an_explicitly_chosen_backend_opens_the_chat(hub, monkeypatch, config):
    from app import assistant_service as ai

    monkeypatch.setattr(ai, 'load_config', lambda: config)
    monkeypatch.setattr(ai, 'check_ollama_status', lambda: {'available': True, 'models': ['gemma2:2b']})
    monkeypatch.setattr(ai, 'check_claude_status', lambda: {'available': True})
    assert 'id="chatMessages"' in hub.get('/hub/assistant').get_data(as_text=True)


def test_install_page_runs_only_scripts_with_the_nonce(hub):
    import re

    response = hub.get('/hub/assistant')
    script_src = re.search(r"script-src ([^;]+)", response.headers['Content-Security-Policy']).group(1)
    assert "'unsafe-inline'" not in script_src
    nonce = re.search(r"'nonce-([^']+)'", script_src).group(1)
    tags = re.findall(r"<[a-zA-Z][^>]*>", response.get_data(as_text=True))
    runnable = [tag for tag in tags if tag.startswith('<script') and 'type="application/json"' not in tag]
    assert runnable and all(f'nonce="{nonce}"' in tag for tag in runnable)
    assert not [tag for tag in tags if re.search(r"\son[a-z]+\s*=", tag)]


def test_installed_assistant_opens_the_chat(hub, monkeypatch):
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / 'model.gguf').write_bytes(b'x')
    page = hub.get('/hub/assistant').get_data(as_text=True)
    assert 'id="chatMessages"' in page
    assert 'data-page-module="assistant"' not in page


def test_a_running_runtime_update_shows_its_progress(hub, monkeypatch):
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / 'model.gguf').write_bytes(b'x')
    monkeypatch.setattr(local_ai.installer, 'running', lambda: True)
    assert 'data-page-module="assistant"' in hub.get('/hub/assistant').get_data(as_text=True)


def test_install_api_needs_a_session():
    from app import app as hub_module

    hub_module.app.config['TESTING'] = True
    with hub_module.app.test_client() as anonymous:
        assert anonymous.get('/api/hub/assistant/install').status_code == 401
        assert anonymous.post('/api/hub/assistant/install').status_code == 401
        assert anonymous.delete('/api/hub/assistant/install').status_code == 401


def test_install_api_refuses_cross_site_requests(hub):
    response = hub.post('/api/hub/assistant/install', headers={'Sec-Fetch-Site': 'cross-site'})
    assert response.status_code == 403
    assert local_ai.installer.job()['state'] == 'idle'


def test_install_api_starts_reports_and_cancels(hub, monkeypatch):
    started = []
    monkeypatch.setattr(local_ai.installer, 'start', lambda: started.append(True) or True)
    status = hub.post('/api/hub/assistant/install').get_json()
    assert started == [True]
    assert status['installed'] is False and 'job' in status
    assert hub.get('/api/hub/assistant/install').headers['Cache-Control'] == 'no-store'
    cancelled = []
    monkeypatch.setattr(local_ai.installer, 'cancel', lambda: cancelled.append(True))
    hub.post('/api/hub/assistant/install/cancel')
    assert cancelled == [True]


def test_uninstall_is_refused_while_installing(hub, monkeypatch):
    monkeypatch.setattr(local_ai.installer, 'running', lambda: True)
    response = hub.delete('/api/hub/assistant/install')
    assert response.status_code == 409


def test_local_backend_counts_only_a_usable_install(isolated, monkeypatch):
    from app import assistant_service as ai

    local_ai.MODELS_DIR.mkdir(parents=True)
    (local_ai.MODELS_DIR / 'model.gguf').write_bytes(b'x')
    assert ai.check_local_status() == {'available': False}
    monkeypatch.setattr(local_ai, 'llama_cpp_available', lambda: True)
    assert ai.check_local_status()['available'] is True
