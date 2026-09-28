# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

"""Standalone entry point for the frozen desktop backend (PyInstaller).

The Flask app package uses relative imports (`from . import database`), so it
cannot be a PyInstaller entry itself. This top-level script imports the package
normally and starts the SocketIO/Werkzeug server. It is a local, single-user
server bound to loopback, so `allow_unsafe_werkzeug=True` is intentional (the
async mode is 'threading', which serves via Werkzeug's runner).

Persistence honors HUB_DATA_DIR (set by the launcher to a writable per-user
directory); see app/paths.py.
"""

import os

from app import local_ai
from app.app import app, socketio


def main() -> None:
    local_ai.install_shutdown_hooks()
    host = os.environ.get("HUB_HOST", "127.0.0.1")
    port = int(os.environ.get("HUB_PORT", "5050"))
    socketio.run(
        app,
        host=host,
        port=port,
        debug=False,
        allow_unsafe_werkzeug=True,
    )


if __name__ == "__main__":
    main()
