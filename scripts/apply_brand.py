# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
BRAND_FILE = ROOT / "brand" / "brand.json"
APPLIED_FILE = ROOT / "app" / "brand.py"

SPDX_HASH = "# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper\n# SPDX-License-Identifier: AGPL-3.0-only\n\n"
SPDX_SLASH = "// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper\n// SPDX-License-Identifier: AGPL-3.0-only\n\n"

PROSE_FILES = [
    "README.md",
    "NOTICE",
    "COMMERCIAL-LICENSE.md",
    "CONTRIBUTING.md",
    "licensing/CLA.md",
    "licensing/commercial-agreement-template.md",
]


def load_brand():
    return json.loads(BRAND_FILE.read_text(encoding="utf-8"))


def applied_name():
    match = re.search(r'^NAME = (".*")$', read(APPLIED_FILE) or "", re.MULTILINE)
    return json.loads(match.group(1)) if match else None


def plain(value):
    return value


def xml_text(value):
    return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def c_string(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def lower_c_string(value):
    return c_string(value.lower())


def json_string(value):
    return json.dumps(value, ensure_ascii=False)[1:-1]


def lower_json_string(value):
    return json_string(value.lower())


def dart_literal(value):
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def generated_files(brand):
    name = json.dumps(brand["name"], ensure_ascii=False)
    repository = json.dumps(brand["repository"], ensure_ascii=False)
    website = json.dumps(brand["website"], ensure_ascii=False)
    previous = brand.get("previousNames", [])
    python_previous = "(" + ", ".join(json.dumps(item, ensure_ascii=False) for item in previous) + ("," if len(previous) == 1 else "") + ")"
    dart_previous = "<String>[" + ", ".join(dart_literal(item) for item in previous) + "]"
    return {
        "app/brand.py": SPDX_HASH
        + f"NAME = {name}\nREPOSITORY = {repository}\nWEBSITE = {website}\nPREVIOUS_NAMES = {python_previous}\n",
        "app/static/js/brand.js": SPDX_SLASH
        + f"self.BRAND_NAME = {name};\nself.BRAND_REPOSITORY = {repository};\nself.BRAND_WEBSITE = {website};\n"
        + f"self.BRAND_PREVIOUS_NAMES = {json.dumps(previous, ensure_ascii=False)};\n",
        "flutter_app/lib/brand.dart": SPDX_SLASH
        + "class Brand {\n  Brand._();\n\n"
        + f"  static const name = {dart_literal(brand['name'])};\n"
        + f"  static const repository = {dart_literal(brand['repository'])};\n"
        + f"  static const website = {dart_literal(brand['website'])};\n"
        + f"  static const previousNames = {dart_previous};\n}}\n",
        "desktop/brand.json": json.dumps({"name": brand["name"], "repository": brand["repository"], "website": brand["website"], "previousNames": previous}, ensure_ascii=False, indent=2) + "\n",
        "promo-video/src/brand.ts": f"export const BRAND_NAME = {name};\nexport const BRAND_WEBSITE = {website};\n",
    }


def slot(path, pattern, escape, count=1, source="name"):
    return {"path": path, "pattern": pattern, "escape": escape, "count": count, "source": source}


def slot_value(brand, source):
    if source == "website_host":
        return urlparse(brand["website"]).netloc
    return brand[source]


SLOTS = [
    slot("flutter_app/android/app/src/main/AndroidManifest.xml", r'(<application\b[^>]*?\bandroid:label=")[^"]*(")', xml_text),
    slot("flutter_app/ios/Runner/Info.plist", r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", xml_text),
    slot("flutter_app/ios/Runner/Info.plist", r"(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)", xml_text),
    slot("flutter_app/macos/Runner/Configs/AppInfo.xcconfig", r"(^PRODUCT_NAME = )[^\r\n]*()", plain),
    slot("flutter_app/macos/Runner.xcodeproj/project.pbxproj", r'(TEST_HOST = "\$\(BUILT_PRODUCTS_DIR\)/)[^"/]*(\.app/)', plain, 3),
    slot("flutter_app/macos/Runner.xcodeproj/project.pbxproj", r'(\.app/\$\(BUNDLE_EXECUTABLE_FOLDER_PATH\)/)[^"]*(")', plain, 3),
    slot("flutter_app/macos/Runner.xcodeproj/project.pbxproj", r"(/\* )[^*\n]*?(\.app \*/)", plain, 3),
    slot("flutter_app/macos/Runner.xcodeproj/project.pbxproj", r"(path = )[^;\n]*?(\.app; sourceTree = BUILT_PRODUCTS_DIR)", plain),
    slot("flutter_app/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme", r'(BuildableName = ")[^"]*?(\.app")', xml_text, 4),
    slot("flutter_app/windows/CMakeLists.txt", r"(^project\()[^ )]+( LANGUAGES CXX\))", lower_c_string),
    slot("flutter_app/windows/CMakeLists.txt", r'(^set\(BINARY_NAME ")[^"]*("\))', lower_c_string),
    slot("flutter_app/macos/Runner/AppDelegate.swift", r'(private let trustedNotificationHosts = \[")[^"]*(")', c_string, source="website_host"),
    slot("flutter_app/windows/runner/main.cpp", r'(window\.Create\(L")[^"]*(")', c_string),
    slot("flutter_app/windows/runner/Runner.rc", r'(VALUE "InternalName", ")[^"]*(")', lower_c_string),
    slot("flutter_app/windows/runner/Runner.rc", r'(VALUE "OriginalFilename", ")[^"]*(\.exe")', lower_c_string),
    slot("flutter_app/windows/runner/Runner.rc", r'(VALUE "ProductName", ")[^"]*(")', c_string),
    slot("flutter_app/linux/CMakeLists.txt", r'(^set\(BINARY_NAME ")[^"]*("\))', lower_c_string),
    slot("flutter_app/windows/runner/Runner.rc", r'(VALUE "FileDescription", ")[^"]*(")', c_string),
    slot("flutter_app/linux/my_application.cc", r'(gtk_header_bar_set_title\(header_bar, ")[^"]*(")', c_string),
    slot("flutter_app/linux/my_application.cc", r'(gtk_window_set_title\(window, ")[^"]*(")', c_string),
    slot("flutter_app/web/index.html", r"(<title>)[^<]*(</title>)", xml_text),
    slot("flutter_app/web/index.html", r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")', xml_text),
    slot("flutter_app/web/index.html", r'(<img class="loading-logo" src="[^"]*" alt=")[^"]*(")', xml_text),
    slot("flutter_app/web/index.html", r'(<div class="loading-text">)[^<]*(</div>)', xml_text),
    slot("flutter_app/web/manifest.json", r'(^    "name": ")[^"]*(")', json_string),
    slot("flutter_app/web/manifest.json", r'(^    "short_name": ")[^"]*(")', json_string),
    slot("landing-page/public/version.json", r'("(?:updateUrl|android|macos|windows|linux|ios|web)": ")[^"]*?(/download)', json_string, 7, source="website"),
    slot("app/static/manifest.json", r'(^  "name": ")[^"]*(")', json_string),
    slot("app/static/manifest.json", r'(^  "short_name": ")[^"]*(")', json_string),
    slot("desktop/package.json", r'("appId": "app\.)[^."]*(\.desktop")', lower_json_string),
    slot("desktop/package.json", r'("productName": ")[^"]*(")', json_string),
    slot("desktop/package.json", r'("shortcutName": ")[^"]*(")', json_string),
    slot("desktop/package.json", r'("artifactName": ")[^"]*(-Setup-\$\{version\}\.exe")', json_string),
    slot("desktop/package.json", r'("artifactName": ")[^"]*(-\$\{version\}\.AppImage")', json_string),
    slot("desktop/package.json", r'("artifactName": ")[^"]*(-\$\{version\}\.deb")', json_string),
    slot("desktop/package.json", r'("desktopName": "app\.)[^."]*(\.desktop")', lower_json_string),
    slot("desktop/package.json", r'("executableName": ")[^"]*(")', lower_json_string),
    slot("desktop/package.json", r'("packageName": ")[^"]*(")', lower_json_string),
    slot("desktop/package.json", r'("homepage": ")[^"]*(")', json_string, source="repository"),
]


def managed_paths():
    return sorted(set(generated_files({"name": "", "repository": "", "website": ""}).keys()) | {entry["path"] for entry in SLOTS} | set(PROSE_FILES))


def read(path):
    return path.read_bytes().decode("utf-8") if path.exists() else None


def planned_contents(brand, previous):
    name = brand["name"]
    contents = dict(generated_files(brand))
    for entry in SLOTS:
        relative = entry["path"]
        text = contents.get(relative)
        if text is None:
            text = read(ROOT / relative)
        if text is None:
            raise SystemExit(f"{relative} fehlt")
        value = entry["escape"](slot_value(brand, entry["source"]))
        text, count = re.subn(entry["pattern"], lambda m: m.group(1) + value + m.group(2), text, flags=re.MULTILINE)
        if count != entry["count"]:
            raise SystemExit(f"{relative}: Muster {entry['pattern']!r} {count}-mal gefunden statt {entry['count']}-mal")
        contents[relative] = text

    for relative in PROSE_FILES:
        text = read(ROOT / relative)
        if text is None:
            raise SystemExit(f"{relative} fehlt")
        if previous and previous != name:
            text = re.sub(rf"\b{re.escape(previous)}\b", lambda m: name, text)
        contents[relative] = text
    return contents


def main(argv=None):
    parser = argparse.ArgumentParser(description="Schreibt den Namen aus brand/brand.json in alle Plattformdateien.")
    parser.add_argument("--check", action="store_true", help="nur prüfen, ob alles zum Namen passt, nichts schreiben")
    args = parser.parse_args(argv)

    brand = load_brand()
    name = brand["name"]
    previous = applied_name()
    known = brand.setdefault("previousNames", [])
    if previous and previous != name and previous not in known:
        known.append(previous)
        if args.check:
            print(f"„{previous}“ fehlt in previousNames in brand/brand.json, bitte python3 scripts/apply_brand.py ausführen.")
            return 1
        BRAND_FILE.write_text(json.dumps(brand, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    outdated = []
    for relative, text in planned_contents(brand, previous).items():
        path = ROOT / relative
        if read(path) == text:
            continue
        outdated.append(relative)
        if not args.check:
            path.write_bytes(text.encode("utf-8"))

    if args.check:
        if outdated:
            print(f"Nicht auf „{name}“ gesetzt, bitte python3 scripts/apply_brand.py ausführen:")
            print("\n".join(f"  {relative}" for relative in outdated))
            return 1
        print(f"Alles auf „{name}“.")
        return 0

    if outdated:
        print(f"Auf „{name}“ gesetzt:")
        print("\n".join(f"  {relative}" for relative in outdated))
    else:
        print(f"Schon alles auf „{name}“.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
