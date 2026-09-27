# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

"""Central resolution of the writable data directory.

Every module that reads/writes files under ``data/``
imports ``DATA_DIR`` / ``PROJECT_ROOT`` from here instead of recomputing
``Path(__file__).parent.parent`` locally. This lets a packaged/frozen desktop
build point persistence at a writable per-user location via the
``HUB_DATA_DIR`` environment variable, and keeps a PyInstaller-frozen binary
from resolving data paths inside its read-only bundle.

Fallback (env unset, running from source) is byte-identical to the previous
behaviour (``Path(__file__).parent.parent``), so the backend test suite is
unaffected.
"""

import os
import re
import sys
from pathlib import Path

from . import brand


def _project_root() -> Path:
    # In a PyInstaller build ``__file__`` points inside the read-only bundle, so
    # anchor to the executable's directory instead.
    if getattr(sys, "frozen", False):
        return Path(sys.executable).parent
    # app/paths.py -> parent.parent is the project root, matching every module
    # that previously did Path(__file__).parent.parent.
    return Path(__file__).parent.parent


def env(name, default=None):
    legacy = [re.sub(r"[^A-Z0-9]+", "_", previous.upper()).strip("_") for previous in brand.PREVIOUS_NAMES]
    prefixes = ["HUB"] + [prefix for prefix in legacy if re.fullmatch(r"[A-Z][A-Z0-9_]*", prefix)]
    for prefix in prefixes:
        value = os.environ.get(f"{prefix}_{name}")
        if value:
            return value
    return default


PROJECT_ROOT = _project_root()

_env_data_dir = env("DATA_DIR")
DATA_DIR = Path(_env_data_dir) if _env_data_dir else (PROJECT_ROOT / "data")

try:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(DATA_DIR, 0o700)
except OSError:
    pass
