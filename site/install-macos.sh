#!/bin/bash
# Hora macOS Installer
# Usage: curl -sL https://hora-app.netlify.app/install-macos.sh | bash

set -e

APP_NAME="Hora"
ZIP_URL="https://hora-app.netlify.app/downloads/Hora-macOS.zip"
INSTALL_DIR="/Applications"
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo ""
echo "  ╔══════════════════════════════════╗"
echo "  ║      Hora Installer für macOS    ║"
echo "  ╚══════════════════════════════════╝"
echo ""

# Download
echo "  → Lade Hora herunter..."
curl -sL -o "$TMP_DIR/Hora-macOS.zip" "$ZIP_URL"

# Verify checksum (update EXPECTED_SHA on each release)
EXPECTED_SHA="46e3b588794330a30b5099ea6a2d041af13e6e6a8b600a528ed3b0172dac9a69"
ACTUAL_SHA=$(shasum -a 256 "$TMP_DIR/Hora-macOS.zip" | awk '{print $1}')
if [ "$EXPECTED_SHA" != "PLACEHOLDER_UPDATE_ON_RELEASE" ] && [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "  !! FEHLER: Prüfsumme stimmt nicht überein! Download möglicherweise manipuliert."
    exit 1
fi

# Unzip
echo "  → Entpacke..."
unzip -q "$TMP_DIR/Hora-macOS.zip" -d "$TMP_DIR"

# Find the .app bundle
APP_PATH=$(find "$TMP_DIR" -name "*.app" -maxdepth 2 -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "  ✗ Fehler: Keine .app gefunden im ZIP."
    exit 1
fi

# Remove old version if exists
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "  → Entferne alte Version..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# Move to Applications
echo "  → Installiere nach $INSTALL_DIR..."
mv "$APP_PATH" "$INSTALL_DIR/$APP_NAME.app"

# Remove quarantine flag so Gatekeeper doesn't block the app on first launch.
# This is standard for CLI installers (Homebrew does the same).
# Only removes the download quarantine — doesn't bypass code signing.
xattr -d com.apple.quarantine "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

echo ""
echo "  ✓ Hora wurde erfolgreich installiert!"
echo "  → Öffne Hora über Launchpad oder Spotlight."
echo ""

# Open the app
open "$INSTALL_DIR/$APP_NAME.app"
