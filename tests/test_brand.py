# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
APPLY_BRAND = ROOT / "scripts" / "apply_brand.py"
SCANNED_SUFFIXES = {
    ".cc", ".cpp", ".css", ".dart", ".html", ".js", ".json", ".kt", ".plist", ".py",
    ".rc", ".sh", ".swift", ".ts", ".tsx", ".xcconfig", ".xml", ".yaml", ".yml",
}
SKIPPED_PREFIXES = ("brand/", "site/", "landing-page/public/", "promo-video/out/")


def managed_paths():
    spec = importlib.util.spec_from_file_location("apply_brand", APPLY_BRAND)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return set(module.managed_paths())


def repository_files():
    try:
        result = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        pytest.skip("git ist nicht verfügbar")
    return result.stdout.splitlines()


def test_platform_files_match_brand_json():
    result = subprocess.run([sys.executable, str(APPLY_BRAND), "--check"], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def test_brand_name_is_not_hardcoded():
    name = json.loads((ROOT / "brand" / "brand.json").read_text(encoding="utf-8"))["name"]
    pattern = re.compile(rf"\b{re.escape(name)}\b")
    managed = managed_paths()
    offenders = []
    for relative in repository_files():
        if relative in managed or relative.startswith(SKIPPED_PREFIXES) or Path(relative).suffix not in SCANNED_SUFFIXES:
            continue
        path = ROOT / relative
        if not path.is_file():
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
            if pattern.search(line):
                offenders.append(f"{relative}:{number}: {line.strip()[:120]}")
    assert not offenders, f"„{name}“ steht fest im Code statt über brand/brand.json:\n" + "\n".join(offenders)
