# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

"""On-demand local assistant.

Nothing of the language model ships with the app. When the user asks for it,
this module downloads the llama.cpp server for the current platform and the
Gemma model, checks both against pinned SHA-256 sums and runs the server on
127.0.0.1 only while the assistant is in use.
"""

import atexit
import collections
import contextlib
import errno
import functools
import hashlib
import importlib.util
import json
import logging
import os
import platform
import re
import secrets
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tarfile
import threading
import time
import zipfile
from pathlib import Path, PurePosixPath

import requests

from . import brand
from .paths import DATA_DIR, env

RUNTIME_TAG = 'b11146'
RUNTIME_URL = 'https://github.com/ggml-org/llama.cpp/releases/download/b11146/{file}'
RUNTIMES = {
    ('darwin', 'arm64'): ('llama-b11146-bin-macos-arm64.tar.gz', 11189714,
                          '1ad3f9eff80edb9dbef4259ad564d1720612ef7eea48fa4afed0e54f5f3d5711'),
    ('darwin', 'x86_64'): ('llama-b11146-bin-macos-x64.tar.gz', 11237237,
                           '305f0e3a17d2c01eb205cd0a62128357f1ec3b55329cb084d94e5ec0115d7a3b'),
    ('linux', 'x86_64'): ('llama-b11146-bin-ubuntu-vulkan-x64.tar.gz', 30598492,
                          'd3ce40fce7403cc93bcf5718fc46c6efb61ed9709f8e5d9f10c86bf0e30e8fb3'),
    ('linux', 'arm64'): ('llama-b11146-bin-ubuntu-arm64.tar.gz', 13598346,
                         '4aeda6fe68831547e49b7fa87607383ca5352b3d72ca5f70d52ed265f58c131f'),
    ('windows', 'x86_64'): ('llama-b11146-bin-win-vulkan-x64.zip', 32127004,
                            '55a378aa095b466979d85075234f66d7655c7a7483222af0c006c0e55b4d7bd6'),
    ('windows', 'arm64'): ('llama-b11146-bin-win-cpu-arm64.zip', 12034624,
                           '1727d241f3bf6d27360e984e851cf013928fd655bf89f8628e70da027f377b7d'),
}
RUNTIME_UNPACKED = 120 * 1024 * 1024

MODEL = {
    'name': 'Gemma 4 E2B',
    'file': 'gemma-4-E2B-it-Q4_K_M.gguf',
    'size': 3106738272,
    'sha256': '740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8',
    'url': 'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/'
           '0314792d7f1f7e229411f620751375812bb9faf2/gemma-4-E2B-it-Q4_K_M.gguf',
}

MODELS_DIR = DATA_DIR / 'models'
RUNTIME_ROOT = DATA_DIR / 'runtime'
RUNTIME_DIR = RUNTIME_ROOT / RUNTIME_TAG
RUNTIME_MARKER = RUNTIME_DIR / '.installed.json'
PID_FILE = RUNTIME_ROOT / 'server.json'
LOG_FILE = RUNTIME_ROOT / 'server.log'
CPU_ONLY_FILE = RUNTIME_ROOT / 'cpu-only'
SERVER_NAME = 'llama-server.exe' if sys.platform == 'win32' else 'llama-server'

DISK_MARGIN = 256 * 1024 * 1024
CHUNK = 1024 * 1024
DOWNLOAD_ATTEMPTS = 6
RETRY_STATUS = {408, 425, 429, 500, 502, 503, 504}
FAILURE_COOLDOWN = 60
CONTEXT_SIZE = 8192
SLEEP_SECONDS = 300
IDLE_SECONDS = 1800
START_TIMEOUT = 240

NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)

log = logging.getLogger(__name__)


class InstallError(Exception):
    def __init__(self, code, **detail):
        super().__init__(code)
        self.code = code
        self.detail = detail


class Cancelled(Exception):
    pass


class ServerError(Exception):
    def __init__(self, reason, log_tail=''):
        super().__init__(reason)
        self.reason = reason
        self.log_tail = log_tail


class _Retry(Exception):
    def __init__(self, delay=None):
        super().__init__(delay)
        self.delay = delay


def _system32(exe):
    return os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32', exe)


def _rosetta():
    try:
        out = subprocess.run(['sysctl', '-n', 'sysctl.proc_translated'], capture_output=True, text=True, timeout=5)
        return out.stdout.strip() == '1'
    except (OSError, subprocess.SubprocessError):
        return False


@functools.lru_cache(maxsize=None)
def platform_key():
    system = {'darwin': 'darwin', 'linux': 'linux', 'win32': 'windows'}.get(sys.platform)
    machine = platform.machine().lower()
    arch = {'x86_64': 'x86_64', 'amd64': 'x86_64', 'arm64': 'arm64', 'aarch64': 'arm64'}.get(machine)
    if system == 'darwin' and arch == 'x86_64' and _rosetta():
        arch = 'arm64'
    return system, arch


def runtime_spec():
    return RUNTIMES.get(platform_key())


def server_exe():
    return RUNTIME_DIR / SERVER_NAME


def runtime_installed():
    return RUNTIME_MARKER.is_file() and server_exe().is_file()


def llama_cpp_available():
    try:
        return importlib.util.find_spec('llama_cpp') is not None
    except (ImportError, ValueError):
        return False


def runtime_kind():
    if runtime_installed():
        return 'server'
    if llama_cpp_available():
        return 'python'
    return None


def model_path():
    if not MODELS_DIR.is_dir():
        return None
    preferred = MODELS_DIR / MODEL['file']
    if preferred.is_file():
        return preferred
    found = sorted(MODELS_DIR.glob('*.gguf'), key=lambda f: (
        0 if 'gemma-4' in f.name.lower() or 'gemma4' in f.name.lower() else 1, f.name))
    return found[0] if found else None


def model_label(path=None):
    path = path or model_path()
    if path is None or path.name == MODEL['file']:
        return MODEL['name']
    return path.stem.replace('-it-Q4_K_M', '').replace('-it-', ' ')


def is_installed():
    return model_path() is not None and runtime_kind() is not None


@functools.lru_cache(maxsize=None)
def total_memory():
    try:
        if sys.platform == 'darwin':
            out = subprocess.run(['sysctl', '-n', 'hw.memsize'], capture_output=True, text=True, timeout=5)
            return int(out.stdout.strip())
        if sys.platform.startswith('linux'):
            with open('/proc/meminfo') as info:
                for line in info:
                    if line.startswith('MemTotal:'):
                        return int(line.split()[1]) * 1024
        if sys.platform == 'win32':
            import ctypes

            class MemoryStatus(ctypes.Structure):
                _fields_ = [('length', ctypes.c_ulong), ('load', ctypes.c_ulong), ('total', ctypes.c_ulonglong),
                            ('available', ctypes.c_ulonglong), ('page_total', ctypes.c_ulonglong),
                            ('page_available', ctypes.c_ulonglong), ('virtual_total', ctypes.c_ulonglong),
                            ('virtual_available', ctypes.c_ulonglong), ('extended', ctypes.c_ulonglong)]

            state = MemoryStatus()
            state.length = ctypes.sizeof(MemoryStatus)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(state)):
                return int(state.total)
    except (OSError, ValueError, subprocess.SubprocessError, AttributeError):
        return None
    return None


def free_space():
    try:
        return shutil.disk_usage(DATA_DIR).free
    except OSError:
        return None


def _part(path):
    return path.with_name(path.name + '.part')


def _size(path):
    try:
        return path.stat().st_size
    except OSError:
        return 0


def _runtime_part(spec):
    return RUNTIME_ROOT / (spec[0] + '.part')


def _model_part():
    return _part(MODELS_DIR / MODEL['file'])


def _remaining():
    runtime = model = 0
    spec = runtime_spec()
    if spec and not runtime_installed():
        runtime = max(spec[1] - _size(_runtime_part(spec)), 0)
    if model_path() is None:
        model = max(MODEL['size'] - _size(_model_part()), 0)
    return runtime, model


def _needed_bytes():
    runtime, model = _remaining()
    spec = runtime_spec()
    unpacked = RUNTIME_UNPACKED if spec and not runtime_installed() else 0
    return runtime + unpacked + model


class _Rate:
    def __init__(self):
        self.samples = collections.deque(maxlen=64)

    def add(self, done):
        now = time.monotonic()
        self.samples.append((now, done))
        while len(self.samples) > 2 and now - self.samples[0][0] > 4:
            self.samples.popleft()

    def speed(self):
        if len(self.samples) < 2:
            return 0
        (t0, b0), (t1, b1) = self.samples[0], self.samples[-1]
        return (b1 - b0) / (t1 - t0) if t1 > t0 else 0


class Installer:
    def __init__(self):
        self._lock = threading.Lock()
        self._cancel = threading.Event()
        self._thread = None
        self._job = self._fresh()
        self._rate = _Rate()
        self._carried = None
        self._holding = False

    @staticmethod
    def _fresh():
        return {'state': 'idle', 'phase': None, 'steps': [], 'done': 0, 'total': 0, 'phase_done': 0,
                'phase_total': 0, 'speed': 0, 'eta': None, 'error': None}

    def job(self):
        with self._lock:
            job = dict(self._job)
            job['steps'] = list(job['steps'])
            return job

    def running(self):
        with self._lock:
            return self._job['state'] == 'running'

    def _set(self, **values):
        with self._lock:
            self._job.update(values)

    def start(self):
        with self._lock:
            if self._job['state'] == 'running' or self._holding:
                return False
            self._cancel.clear()
            self._rate = _Rate()
            self._job = self._fresh()
            self._job.update(state='running', phase='check')
            self._thread = threading.Thread(target=self._run, name='assistant-install', daemon=True)
            self._thread.start()
            return True

    def cancel(self):
        self._cancel.set()

    def hold(self):
        with self._lock:
            if self._job['state'] == 'running' or self._holding:
                return False
            self._holding = True
            return True

    def release(self):
        with self._lock:
            self._holding = False

    def wait(self, timeout=None):
        thread = self._thread
        if thread is not None:
            thread.join(timeout)

    def _run(self):
        try:
            self._install()
            self._set(state='done', phase=None, speed=0, eta=None)
        except Cancelled:
            self._set(state='cancelled', phase=None, speed=0, eta=None)
        except InstallError as error:
            log.warning('Assistant install failed: %s %s', error.code, error.detail)
            self._set(state='error', speed=0, eta=None, error=dict(error.detail, code=error.code))
        except Exception:
            log.exception('Assistant install crashed')
            self._set(state='error', speed=0, eta=None, error={'code': 'unexpected'})

    def _check_cancel(self):
        if self._cancel.is_set():
            raise Cancelled()

    def _install(self):
        spec = runtime_spec()
        if spec is None and not llama_cpp_available():
            raise InstallError('unsupported', platform='-'.join(part or '?' for part in platform_key()))
        need_runtime = spec is not None and not runtime_installed()
        need_model = model_path() is None

        free = free_space()
        needed = _needed_bytes()
        if free is not None and needed and free < needed + DISK_MARGIN:
            raise InstallError('disk_full', missing=needed + DISK_MARGIN - free)

        runtime_bytes, model_bytes = _remaining()
        steps = (['runtime'] if need_runtime else []) + (['model', 'verify'] if need_model else []) + (['start'] if spec else [])
        self._set(steps=steps, total=runtime_bytes + model_bytes, done=0)

        if need_runtime:
            self._install_runtime(spec)
        if need_model:
            self._install_model()

        self._check_cancel()
        if spec is None:
            return
        self._set(phase='start', phase_done=0, phase_total=0, speed=0, eta=None)
        try:
            server.ensure(cancel=self._cancel, force=True)
        except ServerError as error:
            raise InstallError('start_failed', reason=error.reason, log=error.log_tail)

    def _install_runtime(self, spec):
        name, size, sha256 = spec
        RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
        archive = RUNTIME_ROOT / name
        for attempt in range(2):
            self._set(phase='runtime', phase_done=0, phase_total=size)
            try:
                self._download(RUNTIME_URL.format(file=name), archive, size, sha256, 'runtime')
                break
            except InstallError as error:
                if error.code != 'checksum' or attempt:
                    raise
                log.warning('Runtime checksum mismatch, downloading it once more')
                with self._lock:
                    self._job['total'] += size
        staging = RUNTIME_ROOT / (RUNTIME_TAG + '.staging')
        shutil.rmtree(staging, ignore_errors=True)
        try:
            unpack(archive, staging, self._check_cancel)
            exe = staging / SERVER_NAME
            if not exe.is_file():
                raise InstallError('runtime_broken', reason='missing_server')
            _add_windows_runtime_libraries(staging)
            _probe_runtime(exe)
            (staging / RUNTIME_MARKER.name).write_text(json.dumps({'tag': RUNTIME_TAG, 'archive': name,
                                                                   'sha256': sha256}))
            server.stop()
            shutil.rmtree(RUNTIME_DIR, ignore_errors=True)
            os.replace(staging, RUNTIME_DIR)
            with contextlib.suppress(OSError):
                CPU_ONLY_FILE.unlink()
        finally:
            shutil.rmtree(staging, ignore_errors=True)
            with contextlib.suppress(OSError):
                archive.unlink()
        for old in RUNTIME_ROOT.iterdir():
            if old.is_dir() and old.name != RUNTIME_TAG and old.name[:1] == 'b' and old.name[1:].isdigit():
                shutil.rmtree(old, ignore_errors=True)

    def _install_model(self):
        MODELS_DIR.mkdir(parents=True, exist_ok=True)
        target = MODELS_DIR / MODEL['file']
        for attempt in range(2):
            self._set(phase='model', phase_done=0, phase_total=MODEL['size'])
            try:
                self._download(MODEL['url'], target, MODEL['size'], MODEL['sha256'], 'model')
                return
            except InstallError as error:
                if error.code != 'checksum' or attempt:
                    raise
                log.warning('Model checksum mismatch, downloading it once more')
                with self._lock:
                    self._job['total'] += MODEL['size']

    def _download(self, url, target, size, sha256, phase):
        part = _part(target)
        self._carried = None
        failures = 0
        while True:
            self._check_cancel()
            start = _size(part)
            try:
                self._fetch(url, part, size, sha256, phase)
                break
            except (requests.ConnectionError, requests.Timeout, requests.exceptions.ChunkedEncodingError,
                    _Retry) as error:
                failures = 1 if _size(part) > start else failures + 1
                log.info('Download interrupted (%s), attempt %d', type(error).__name__, failures)
                if failures >= DOWNLOAD_ATTEMPTS:
                    raise InstallError('offline')
                self._wait_before_retry(failures, getattr(error, 'delay', None))
            except OSError as error:
                if error.errno == errno.ENOSPC:
                    raise InstallError('disk_full')
                raise
        self._carried = None
        os.replace(part, target)

    def _wait_before_retry(self, failures, delay=None):
        if self._cancel.wait(min(delay, 60) if delay else min(2 ** failures, 30)):
            raise Cancelled()

    def _advance(self, phase_done, delta):
        with self._lock:
            self._job['phase_done'] = phase_done
            self._job['done'] += delta
            self._rate.add(self._job['done'])
            speed = self._rate.speed()
            remaining = max(self._job['total'] - self._job['done'], 0)
            self._job['speed'] = int(speed)
            self._job['eta'] = int(remaining / speed) if speed > 16 * 1024 else None

    def _hash_existing(self, part, offset, phase):
        digest = hashlib.sha256()
        self._set(phase='resume' if phase == 'model' else phase, phase_done=0)
        with open(part, 'rb') as existing:
            hashed = 0
            while hashed < offset:
                self._check_cancel()
                block = existing.read(min(CHUNK * 8, offset - hashed))
                if not block:
                    raise _Retry()
                digest.update(block)
                hashed += len(block)
                self._set(phase_done=hashed)
        self._set(phase=phase)
        return digest

    def _fetch(self, url, part, size, sha256, phase):
        offset = _size(part)
        if offset > size:
            part.unlink()
            offset = 0
        carried = getattr(self, '_carried', None)
        if offset and carried and carried[0] == offset:
            digest = carried[1]
        elif offset:
            digest = self._hash_existing(part, offset, phase)
        else:
            digest = hashlib.sha256()
        self._carried = (offset, digest)

        if offset < size:
            headers = {'User-Agent': f'{brand.NAME} (+{brand.REPOSITORY})', 'Accept-Encoding': 'identity'}
            if offset:
                headers['Range'] = f'bytes={offset}-'
            with requests.get(url, headers=headers, stream=True, timeout=(15, 60)) as response:
                if response.status_code == 416:
                    part.unlink()
                    raise _Retry()
                if response.status_code in RETRY_STATUS:
                    after = response.headers.get('Retry-After', '').strip()
                    raise _Retry(int(after) if after.isdigit() else None)
                if response.status_code not in (200, 206):
                    raise InstallError('http', status=response.status_code)
                if offset and response.status_code == 200:
                    offset = 0
                    digest = hashlib.sha256()
                    part.write_bytes(b'')
                    self._carried = (offset, digest)
                elif response.status_code == 206:
                    unit_range = response.headers.get('Content-Range', '').split(' ')[-1]
                    if unit_range.split('-')[0] != str(offset):
                        part.unlink()
                        raise _Retry()
                self._set(phase_done=offset)
                with open(part, 'ab') as out:
                    for block in response.iter_content(CHUNK):
                        self._check_cancel()
                        if not block:
                            continue
                        if offset + len(block) > size:
                            out.close()
                            part.unlink()
                            raise InstallError('checksum')
                        out.write(block)
                        digest.update(block)
                        offset += len(block)
                        self._carried = (offset, digest)
                        self._advance(offset, len(block))

        if offset != size:
            raise _Retry()
        if phase == 'model':
            self._set(phase='verify', speed=0, eta=None)
        if digest.hexdigest() != sha256:
            with contextlib.suppress(OSError):
                part.unlink()
            raise InstallError('checksum')


def _safe_member(name):
    path = PurePosixPath(name.replace('\\', '/'))
    if path.is_absolute() or not path.parts or '..' in path.parts or ':' in path.parts[0]:
        return None
    return path


def _strip_top(paths):
    tops = {path.parts[0] for path in paths}
    return 1 if len(tops) == 1 and any(len(path.parts) > 1 for path in paths) else 0


def _wanted(name):
    lower = name.lower()
    return (lower in ('llama-server', 'llama-server.exe') or lower.startswith('license')
            or lower.endswith(('.dll', '.dylib', '.so')) or '.so.' in lower)


def _destination(root, name):
    destination = (root / name).resolve()
    if destination.parent != root:
        raise InstallError('runtime_broken', reason='unsafe_path')
    return destination


def _members(names):
    paths = [_safe_member(name) for name in names]
    if any(path is None for path in paths):
        raise InstallError('runtime_broken', reason='unsafe_path')
    strip = _strip_top(paths)
    names = []
    for path in paths:
        rest = path.parts[strip:]
        names.append(rest[0] if len(rest) == 1 and _wanted(rest[0]) else None)
    return names


def unpack(archive, target, check_cancel=lambda: None):
    target.mkdir(parents=True, exist_ok=True)
    root = target.resolve()
    if archive.name.endswith('.zip'):
        _unpack_zip(archive, root, check_cancel)
    else:
        _unpack_tar(archive, root, check_cancel)


def _unpack_zip(archive, root, check_cancel):
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        for entry, name in zip(entries, _members(entry.filename for entry in entries)):
            check_cancel()
            if name is None or entry.is_dir():
                continue
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise InstallError('runtime_broken', reason='link_in_zip')
            with bundle.open(entry) as source, open(_destination(root, name), 'wb') as out:
                shutil.copyfileobj(source, out, CHUNK)


def _unpack_tar(archive, root, check_cancel):
    with tarfile.open(archive, 'r:*') as bundle:
        members = bundle.getmembers()
        links = []
        for member, name in zip(members, _members(member.name for member in members)):
            check_cancel()
            if name is None or member.isdir():
                continue
            if member.issym():
                link = PurePosixPath(member.linkname)
                if link.is_absolute() or len(link.parts) != 1 or link.name in ('.', '..'):
                    raise InstallError('runtime_broken', reason='unsafe_link')
                links.append((name, link.name))
            elif member.isfile():
                destination = _destination(root, name)
                with bundle.extractfile(member) as source, open(destination, 'wb') as out:
                    shutil.copyfileobj(source, out, CHUNK)
                os.chmod(destination, 0o755 if member.mode & 0o111 else 0o644)
            else:
                raise InstallError('runtime_broken', reason='unexpected_member')
        for name, link in links:
            destination = _destination(root, name)
            with contextlib.suppress(FileNotFoundError):
                destination.unlink()
            os.symlink(link, destination)
        for name, _ in links:
            resolved = (root / name).resolve()
            if resolved.parent != root or not resolved.is_file():
                raise InstallError('runtime_broken', reason='dangling_link')


SECRET_MARKERS = ('SECRET', 'TOKEN', 'PASSWORD', 'PASSWD', 'API_KEY', 'APIKEY', 'CREDENTIAL', 'PRIVATE_KEY')


def _private_prefixes():
    names = ['HUB'] + [re.sub(r'[^A-Z0-9]+', '_', name.upper()).strip('_') for name in brand.PREVIOUS_NAMES]
    return tuple(f'{name}_' for name in names if name) + ('LLAMA_', 'GGML_')


def _runtime_env(directory):
    prefixes = _private_prefixes()
    child = {}
    for key, value in os.environ.items():
        upper = key.upper()
        if upper.startswith(prefixes) or any(marker in upper for marker in SECRET_MARKERS):
            continue
        child[key] = value
    if sys.platform.startswith('linux'):
        if getattr(sys, 'frozen', False):
            original = os.environ.get('LD_LIBRARY_PATH_ORIG')
            child.pop('LD_LIBRARY_PATH_ORIG', None)
            if original:
                child['LD_LIBRARY_PATH'] = original
            else:
                child.pop('LD_LIBRARY_PATH', None)
        existing = child.get('LD_LIBRARY_PATH')
        child['LD_LIBRARY_PATH'] = str(directory) + (os.pathsep + existing if existing else '')
    return child


WINDOWS_RUNTIME_LIBRARIES = ('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
MISSING_LIBRARY_CODES = {0xC0000135, 0xC0000139, -1073741515, -1073741511}


def _add_windows_runtime_libraries(directory):
    bundle = getattr(sys, '_MEIPASS', None)
    if sys.platform != 'win32' or not bundle:
        return
    present = {entry.name.lower(): entry for entry in Path(bundle).iterdir() if entry.is_file()}
    for name in WINDOWS_RUNTIME_LIBRARIES:
        source = present.get(name)
        if source is not None and not (directory / name).exists():
            shutil.copyfile(source, directory / name)


def _probe_runtime(exe):
    try:
        result = subprocess.run([str(exe), '--version'], cwd=str(exe.parent), env=_runtime_env(exe.parent),
                                stdin=subprocess.DEVNULL, capture_output=True, text=True, errors='replace',
                                timeout=60, creationflags=NO_WINDOW)
    except (OSError, subprocess.SubprocessError) as error:
        raise InstallError('runtime_broken', reason=type(error).__name__)
    output = (result.stdout or '') + (result.stderr or '')
    if sys.platform == 'win32' and result.returncode in MISSING_LIBRARY_CODES:
        raise InstallError('runtime_libraries')
    if result.returncode != 0 or 'version' not in output:
        raise InstallError('runtime_broken', reason=output.strip()[-400:])


def _log_tail(limit=1200):
    try:
        with open(LOG_FILE, 'rb') as handle:
            handle.seek(0, os.SEEK_END)
            handle.seek(max(handle.tell() - limit, 0))
            return handle.read().decode('utf-8', 'replace')
    except OSError:
        return ''


def _free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def _windows_image(pid):
    try:
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR,
                                                        ctypes.POINTER(wintypes.DWORD)]
        kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            return ''
        try:
            size = wintypes.DWORD(32768)
            buffer = ctypes.create_unicode_buffer(size.value)
            if kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
                return buffer.value
            return ''
        finally:
            kernel32.CloseHandle(handle)
    except (OSError, AttributeError, ValueError, TypeError):
        return ''


def _process_command(pid):
    if sys.platform == 'win32':
        return _windows_image(pid)
    cmdline = Path(f'/proc/{pid}/cmdline')
    if cmdline.exists():
        with contextlib.suppress(OSError):
            return cmdline.read_bytes().replace(b'\0', b' ').decode('utf-8', 'replace').strip()
    try:
        return subprocess.run(['ps', '-o', 'command=', '-p', str(pid)], capture_output=True, text=True,
                              errors='replace', timeout=15).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ''


def _kill(pid):
    if sys.platform == 'win32':
        subprocess.run([_system32('taskkill.exe'), '/PID', str(pid), '/F'], capture_output=True, timeout=15,
                       creationflags=NO_WINDOW)
        return
    with contextlib.suppress(ProcessLookupError, PermissionError):
        os.kill(pid, signal.SIGTERM)
        for _ in range(30):
            time.sleep(0.1)
            os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)


def reap_stale_server():
    try:
        record = json.loads(PID_FILE.read_text())
        pid = int(record['pid'])
        exe = str(record['exe'])
    except (OSError, ValueError, KeyError, TypeError):
        return False
    command = _process_command(pid)
    if sys.platform == 'win32':
        ours = bool(exe) and bool(command) and os.path.normcase(command) == os.path.normcase(exe)
    else:
        ours = bool(exe) and exe in command
    if ours and pid != os.getpid():
        log.info('Stopping a leftover assistant server (pid %d)', pid)
        with contextlib.suppress(OSError, subprocess.SubprocessError):
            _kill(pid)
    with contextlib.suppress(OSError):
        PID_FILE.unlink()
    return ours


def _kill_on_close_job():
    try:
        import ctypes
        from ctypes import wintypes

        class IoCounters(ctypes.Structure):
            _fields_ = [(name, ctypes.c_ulonglong) for name in (
                'ReadOperationCount', 'WriteOperationCount', 'OtherOperationCount',
                'ReadTransferCount', 'WriteTransferCount', 'OtherTransferCount')]

        class BasicLimits(ctypes.Structure):
            _fields_ = [('PerProcessUserTimeLimit', wintypes.LARGE_INTEGER),
                        ('PerJobUserTimeLimit', wintypes.LARGE_INTEGER), ('LimitFlags', wintypes.DWORD),
                        ('MinimumWorkingSetSize', ctypes.c_size_t), ('MaximumWorkingSetSize', ctypes.c_size_t),
                        ('ActiveProcessLimit', wintypes.DWORD), ('Affinity', ctypes.c_size_t),
                        ('PriorityClass', wintypes.DWORD), ('SchedulingClass', wintypes.DWORD)]

        class ExtendedLimits(ctypes.Structure):
            _fields_ = [('BasicLimitInformation', BasicLimits), ('IoInfo', IoCounters),
                        ('ProcessMemoryLimit', ctypes.c_size_t), ('JobMemoryLimit', ctypes.c_size_t),
                        ('PeakProcessMemoryUsed', ctypes.c_size_t), ('PeakJobMemoryUsed', ctypes.c_size_t)]

        kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel32.CreateJobObjectW.restype = wintypes.HANDLE
        kernel32.CreateJobObjectW.argtypes = [wintypes.LPVOID, wintypes.LPCWSTR]
        kernel32.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD]
        kernel32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        job = kernel32.CreateJobObjectW(None, None)
        if not job:
            return None
        limits = ExtendedLimits()
        limits.BasicLimitInformation.LimitFlags = 0x2000
        if not kernel32.SetInformationJobObject(job, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            return None
        return kernel32, job
    except (OSError, AttributeError, ValueError, TypeError):
        return None


_job = None


def _bind_to_backend(proc):
    """On Windows the server dies with the backend: a job object closes with our process."""
    global _job
    if sys.platform != 'win32':
        return
    if _job is None:
        _job = _kill_on_close_job() or False
    if not _job:
        return
    kernel32, job = _job
    try:
        if not kernel32.AssignProcessToJobObject(job, int(proc._handle)):
            log.info('Could not tie the assistant server to the backend')
    except (OSError, AttributeError, ValueError, TypeError):
        log.info('Could not tie the assistant server to the backend')


def _terminate(proc):
    if proc is None:
        return
    if proc.poll() is None:
        with contextlib.suppress(OSError):
            proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(OSError):
                proc.kill()
            with contextlib.suppress(subprocess.TimeoutExpired):
                proc.wait(timeout=5)


class Server:
    def __init__(self):
        self._lock = threading.Lock()
        self._start_lock = threading.Lock()
        self._proc = None
        self._port = None
        self._key = None
        self._ready = False
        self._starting = False
        self._active = 0
        self._last_used = 0.0
        self._reaped = False
        self._blocked = False
        self._failure = None
        self._local = requests.Session()
        self._local.trust_env = False

    def state(self):
        with self._lock:
            if self._proc is not None and self._proc.poll() is None:
                return 'ready' if self._ready else 'starting'
            return 'starting' if self._starting else 'stopped'

    def _healthy(self, base):
        try:
            return self._local.get(base + '/health', timeout=2).status_code == 200
        except requests.RequestException:
            return False

    def _running(self):
        return self._proc is not None and self._proc.poll() is None and self._ready

    def ensure(self, cancel=None, force=False):
        with self._start_lock:
            with self._lock:
                if self._blocked:
                    raise ServerError('not_installed')
                if self._running():
                    self._last_used = time.monotonic()
                    return f'http://127.0.0.1:{self._port}', self._key
                stale = self._detach()
                failure = self._failure
            _terminate(stale)
            if failure and not force and time.monotonic() - failure[0] < FAILURE_COOLDOWN:
                raise failure[1]
            if not self._reaped:
                self._reaped = True
                reap_stale_server()
            model = model_path()
            if model is None or not runtime_installed():
                raise ServerError('not_installed')
            cpu_only = CPU_ONLY_FILE.exists()
            try:
                try:
                    proc, base, key = self._launch(model, cpu_only, cancel)
                except ServerError as error:
                    if cpu_only or error.reason not in ('exited', 'timeout'):
                        raise
                    log.warning('Assistant server failed with the GPU (%s), trying the CPU only', error.reason)
                    proc, base, key = self._launch(model, True, cancel)
                    with contextlib.suppress(OSError):
                        CPU_ONLY_FILE.write_text('The GPU backend failed while loading the model.\n')
            except ServerError as error:
                if error.reason in ('exited', 'timeout', 'spawn_failed'):
                    with self._lock:
                        self._failure = (time.monotonic(), error)
                raise
            with self._lock:
                self._failure = None
            threading.Thread(target=self._watch_idle, args=(proc,), name='assistant-idle', daemon=True).start()
            return base, key

    def reap_once(self):
        with self._start_lock:
            if self._reaped:
                return
            self._reaped = True
            reap_stale_server()

    @contextlib.contextmanager
    def blocked(self):
        with self._lock:
            self._blocked = True
            proc = self._detach()
        _terminate(proc)
        try:
            with self._start_lock:
                yield
        finally:
            with self._lock:
                self._blocked = False
                self._failure = None

    def _launch(self, model, cpu_only, cancel):
        with self._lock:
            self._starting = True
            try:
                proc, port, key = self._spawn(server_exe(), model, cpu_only)
            except OSError as error:
                self._starting = False
                raise ServerError('spawn_failed', str(error))
        base = f'http://127.0.0.1:{port}'
        try:
            self._await_ready(proc, base, cancel)
        except BaseException as error:
            with self._lock:
                self._starting = False
                stopped = self._proc is not proc
                if not stopped:
                    self._detach()
            _terminate(proc)
            if stopped and isinstance(error, ServerError):
                raise ServerError('stopped') from error
            raise
        with self._lock:
            self._starting = False
            if self._proc is not proc:
                raise ServerError('stopped')
            self._ready = True
            self._last_used = time.monotonic()
        return proc, base, key

    def _spawn(self, exe, model, cpu_only=False):
        RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
        self._port = _free_port()
        self._key = secrets.token_hex(24)
        child_env = _runtime_env(exe.parent)
        child_env['LLAMA_API_KEY'] = self._key
        args = [str(exe), '-m', model.name, '--host', '127.0.0.1', '--port', str(self._port),
                '-c', str(CONTEXT_SIZE), '-np', '1', '--no-webui', '--no-slots', '-cram', '0',
                '--reasoning', 'off', '--sleep-idle-seconds', str(SLEEP_SECONDS)]
        if cpu_only:
            args += ['--device', 'none', '-ngl', '0']
        with open(LOG_FILE, 'wb') as log_handle:
            self._proc = subprocess.Popen(args, cwd=str(model.parent), env=child_env, stdin=subprocess.DEVNULL,
                                          stdout=log_handle, stderr=subprocess.STDOUT, creationflags=NO_WINDOW)
        _bind_to_backend(self._proc)
        self._ready = False
        with contextlib.suppress(OSError):
            PID_FILE.write_text(json.dumps({'pid': self._proc.pid, 'exe': str(exe)}))
        log.info('Assistant server starting (pid %d, port %d)', self._proc.pid, self._port)
        return self._proc, self._port, self._key

    def _await_ready(self, proc, base, cancel):
        deadline = time.monotonic() + START_TIMEOUT
        while time.monotonic() < deadline:
            if cancel is not None and cancel.is_set():
                raise Cancelled()
            if proc.poll() is not None:
                raise ServerError('exited', _log_tail())
            if self._healthy(base):
                return
            time.sleep(0.25)
        raise ServerError('timeout', _log_tail())

    def _watch_idle(self, proc):
        while True:
            time.sleep(30)
            with self._lock:
                if self._proc is not proc or proc.poll() is not None:
                    return
                if self._active or time.monotonic() - self._last_used < IDLE_SECONDS:
                    continue
                log.info('Assistant idle, stopping its server')
                self._detach()
            _terminate(proc)
            return

    def _detach(self):
        proc, self._proc = self._proc, None
        self._ready = False
        if proc is not None:
            with contextlib.suppress(OSError):
                PID_FILE.unlink()
        return proc

    def stop(self):
        with self._lock:
            proc = self._detach()
        _terminate(proc)

    @contextlib.contextmanager
    def _use(self):
        with self._lock:
            self._active += 1
        try:
            yield
        finally:
            with self._lock:
                self._active -= 1
                self._last_used = time.monotonic()

    def stream(self, messages, max_tokens=4096, temperature=0.7, top_p=0.9):
        body = {'messages': messages, 'stream': True, 'max_tokens': max_tokens,
                'temperature': temperature, 'top_p': top_p}
        with self._use():
            base, key = self.ensure()
            with self._local.post(base + '/v1/chat/completions', json=body, stream=True, timeout=(5, 300),
                                  headers={'Authorization': f'Bearer {key}'}) as response:
                response.raise_for_status()
                for line in response.iter_lines():
                    if not line.startswith(b'data: '):
                        continue
                    payload = line[6:].strip()
                    if payload == b'[DONE]':
                        break
                    try:
                        choice = json.loads(payload)['choices'][0]
                    except (ValueError, KeyError, IndexError, TypeError):
                        continue
                    content = (choice.get('delta') or {}).get('content')
                    if content:
                        yield content

    def chat(self, messages, **options):
        return ''.join(self.stream(messages, **options))


installer = Installer()
server = Server()


def warm_up():
    if not runtime_installed() or model_path() is None or server.state() != 'stopped':
        return False

    def run():
        try:
            server.ensure()
        except (ServerError, Cancelled) as error:
            log.info('Assistant warm-up failed: %s', error)
        except Exception:
            log.exception('Assistant warm-up crashed')

    threading.Thread(target=run, name='assistant-warmup', daemon=True).start()
    return True


def status():
    spec = runtime_spec()
    model = model_path()
    kind = runtime_kind()
    runtime_bytes, model_bytes = _remaining()
    return {
        'installed': model is not None and kind is not None,
        'supported': spec is not None or kind == 'python',
        'runtime': {'installed': kind is not None, 'kind': kind, 'download': runtime_bytes},
        'model': {
            'installed': model is not None,
            'name': model_label(model),
            'size': _size(model) if model else MODEL['size'],
            'download': model_bytes,
            'partial': 0 if model else _size(_model_part()),
        },
        'free': free_space(),
        'memory': total_memory(),
        'needed': _needed_bytes(),
        'job': installer.job(),
        'server': server.state(),
    }


def uninstall(on_remove=None):
    if not installer.hold():
        return False
    try:
        with server.blocked():
            if on_remove is not None:
                on_remove()
            shutil.rmtree(MODELS_DIR, ignore_errors=True)
            shutil.rmtree(RUNTIME_ROOT, ignore_errors=True)
    finally:
        installer.release()
    return model_path() is None and not runtime_installed()


def shutdown():
    installer.cancel()
    server.stop()


def _exit_with_parent():
    stream = getattr(sys.stdin, 'buffer', None)
    if env('EXIT_WITH_PARENT') != '1' or stream is None:
        return

    def wait_for_eof():
        try:
            while stream.read(4096):
                pass
        except (OSError, ValueError):
            pass
        log.warning('The app that started the backend is gone, shutting down')
        shutdown()
        os._exit(0)

    threading.Thread(target=wait_for_eof, name='parent-watch', daemon=True).start()


def install_shutdown_hooks():
    atexit.register(shutdown)
    threading.Thread(target=server.reap_once, name='assistant-reap', daemon=True).start()
    _exit_with_parent()

    def stop_and_exit(signum, frame):
        shutdown()
        raise SystemExit(0)

    for name in ('SIGTERM', 'SIGHUP'):
        number = getattr(signal, name, None)
        if number is None:
            continue
        with contextlib.suppress(ValueError, OSError):
            if signal.getsignal(number) != signal.SIG_IGN:
                signal.signal(number, stop_and_exit)
