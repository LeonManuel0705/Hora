# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

"""Prints the one-time login URL for the hub.

Run this when a client cannot present the token itself, for instance an
installed desktop build older than the token handover.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.crypto_utils import decrypt_file  # noqa: E402
from app.paths import DATA_DIR  # noqa: E402


def main() -> int:
    port = os.environ.get("HUB_PORT", "5050")
    token_file = DATA_DIR / ".api_token"
    data = None
    try:
        data = decrypt_file(token_file)
    except Exception as exc:
        print(f"Token konnte nicht gelesen werden: {exc}", file=sys.stderr)
        return 1
    if not data or not data.get("token"):
        print(f"Kein Token in {token_file}. Starte den Hub einmal.", file=sys.stderr)
        return 1
    print(f"http://localhost:{port}/hub?token={data['token']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
