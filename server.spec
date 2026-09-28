# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec: freeze the Flask backend into a standalone `server`.

Produces a onedir bundle (dist/server/) so the Electron/desktop app can
start the backend without a system Python. The frozen binary honors
HUB_DATA_DIR for writable persistence (see app/paths.py).
"""
import os
import sys

from PyInstaller.utils.hooks import collect_all

datas = [
    ('app/templates', 'app/templates'),
    ('app/static', 'app/static'),
    ('app/curriculum', 'app/curriculum'),
]
binaries = []
if sys.platform == 'win32':
    # llama-server needs the Visual C++ runtime; app/local_ai.py places these next to it
    system32 = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32')
    for library in ('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'):
        if os.path.exists(os.path.join(system32, library)):
            binaries.append((os.path.join(system32, library), '.'))
hiddenimports = [
    # flask-socketio async_mode='threading' loads this driver dynamically.
    'engineio.async_drivers.threading',
]

# Packages with dynamic imports / bundled data files that PyInstaller's static
# analysis misses. collect_all grabs submodules + data + binaries.
for pkg in [
    'googleapiclient', 'google_auth_httplib2', 'google_auth_oauthlib',
    'anthropic', 'IServAPI', 'engineio', 'socketio', 'flask_socketio',
    'flask_limiter', 'bs4', 'certifi',
]:
    try:
        d, b, h = collect_all(pkg)
        datas += d
        binaries += b
        hiddenimports += h
    except Exception:
        pass

a = Analysis(
    ['desktop_entry.py'],
    pathex=['.'],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Optional local LLM — lazily imported, not needed for the desktop server
        # and huge. gunicorn/gevent/eventlet are production-server deps unused in
        # threading mode. psycopg2 only loads when DATABASE_URL is set (never on
        # desktop). pytest is test-only.
        'llama_cpp', 'gunicorn', 'gevent', 'gevent_websocket', 'eventlet',
        'psycopg2', 'pytest', 'pytest_xdist', 'tkinter', 'matplotlib',
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='server',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='server',
)
