#!/bin/bash
#
# generate_keystore.sh — create a release keystore for signing the Android app.
#
# Run this ONCE, locally. Keep the resulting .jks and its passwords safe and
# BACKED UP: if you lose them you can never ship an update to an already-installed
# app (Play Store / self-update both reject a build signed by a different key).
#
# Usage:
#   ./generate_keystore.sh [alias] [validity_days] [keystore_path]
#
# Defaults: alias=<name>  validity_days=10000 (~27 years)  keystore_path=~/<name>-release.jks
# where <name> is the lowercase product name from brand/brand.json.
#
# Passwords are read from the environment if set, otherwise you are prompted:
#   RELEASE_STORE_PASSWORD   password for the keystore file
#   RELEASE_KEY_PASSWORD     password for the key entry (defaults to store password if unset)
#
set -euo pipefail

BRAND_NAME="$(sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' "$(dirname "$0")/../../brand/brand.json")"
BRAND_LOWER="$(printf '%s' "$BRAND_NAME" | tr '[:upper:]' '[:lower:]')"

ALIAS="${1:-$BRAND_LOWER}"
VALIDITY="${2:-10000}"
KEYSTORE_PATH="${3:-$HOME/$BRAND_LOWER-release.jks}"

# Expand a leading ~ if the path was passed quoted.
KEYSTORE_PATH="${KEYSTORE_PATH/#\~/$HOME}"

command -v keytool >/dev/null 2>&1 || {
  echo "ERROR: keytool not found. Install a JDK (e.g. Temurin 17) and ensure keytool is on PATH." >&2
  exit 1
}

if [ -e "$KEYSTORE_PATH" ]; then
  echo "ERROR: $KEYSTORE_PATH already exists. Refusing to overwrite an existing keystore." >&2
  echo "       Delete it manually only if you are certain it is unused." >&2
  exit 1
fi

# --- Passwords -------------------------------------------------------------
STORE_PASSWORD="${RELEASE_STORE_PASSWORD:-}"
if [ -z "$STORE_PASSWORD" ]; then
  read -r -s -p "Keystore (store) password: " STORE_PASSWORD; echo
  read -r -s -p "Confirm store password:    " STORE_PASSWORD_CONFIRM; echo
  [ "$STORE_PASSWORD" = "$STORE_PASSWORD_CONFIRM" ] || { echo "Passwords do not match." >&2; exit 1; }
fi
[ ${#STORE_PASSWORD} -ge 6 ] || { echo "Store password must be at least 6 characters." >&2; exit 1; }

KEY_PASSWORD="${RELEASE_KEY_PASSWORD:-$STORE_PASSWORD}"

# --- Generate --------------------------------------------------------------
# -dname is supplied non-interactively; adjust O/OU/etc. to taste. It is only
# metadata embedded in the certificate and does not affect signing behavior.
keytool -genkeypair -v \
  -keystore "$KEYSTORE_PATH" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 \
  -validity "$VALIDITY" \
  -storetype JKS \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=$BRAND_NAME, OU=$BRAND_NAME, O=$BRAND_NAME, L=Unknown, ST=Unknown, C=DE"

chmod 600 "$KEYSTORE_PATH"

echo
echo "=== Keystore created: $KEYSTORE_PATH ==="
echo
echo "Write the following to android/key.properties (this file is gitignored):"
echo "-----------------------------------------------------------------------"
cat <<PROPS
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$ALIAS
storeFile=$KEYSTORE_PATH
PROPS
echo "-----------------------------------------------------------------------"
echo
echo "For CI, base64-encode the keystore and store it as a GitHub secret:"
echo "  base64 -i \"$KEYSTORE_PATH\" | pbcopy      # macOS, copies to clipboard"
echo "  base64 -w0 \"$KEYSTORE_PATH\"              # Linux, prints one line"
echo
echo "Then add secrets: ANDROID_KEYSTORE_BASE64, ANDROID_KEY_ALIAS ($ALIAS),"
echo "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_PASSWORD."
