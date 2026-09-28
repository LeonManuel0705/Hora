#!/bin/bash

set -e
source "$(dirname "$0")/build_common.sh"

BUILD_MODE="${1:---release}"
prepare_build "build_macos.sh"

cd "$PROJECT_DIR"
flutter clean
flutter build macos $BUILD_MODE --build-number="$BUILD_NUM"

REPO_ROOT="$(dirname "$PROJECT_DIR")"
PRODUCT_NAME="$(sed -n 's/^PRODUCT_NAME = //p' "$PROJECT_DIR/macos/Runner/Configs/AppInfo.xcconfig")"
APP_BUNDLE="$PROJECT_DIR/build/macos/Build/Products/Release/$PRODUCT_NAME.app"
BACKEND_DEST="$APP_BUNDLE/Contents/Resources/backend"

echo "=== Bundling backend into app ==="
rm -rf "$BACKEND_DEST"
mkdir -p "$BACKEND_DEST"

cp -R "$REPO_ROOT/app" "$BACKEND_DEST/app"
cp "$REPO_ROOT/requirements.txt" "$BACKEND_DEST/requirements.txt"
cp "$REPO_ROOT/calendar_sync.py" "$BACKEND_DEST/calendar_sync.py" 2>/dev/null || true

echo "Backend bundled ($(du -sh "$BACKEND_DEST" | cut -f1))"

# Only the phone assistant loads llamadart's llama.cpp runtime (the Mac assistant
# runs in the backend), so the 27 MB framework built for macOS 13.3 stays out.
echo "=== Removing the phone-only llama.cpp runtime ==="
rm -rf "$APP_BUNDLE/Contents/Frameworks/llamadart.framework"

# ------------------------------------------------------------------
# Code signing + notarization (gated on env vars; skips cleanly).
# Set MACOS_SIGN_IDENTITY to a "Developer ID Application: …" identity to sign.
# For notarization set MACOS_NOTARY_PROFILE (a `notarytool store-credentials`
# profile) OR APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD.
# ------------------------------------------------------------------
ENTITLEMENTS="$PROJECT_DIR/macos/Runner/Release.entitlements"

# Bundling the backend and dropping the framework break the seal Xcode made.
# Without a valid seal, macOS calls a browser-downloaded copy "damaged" instead
# of offering "Open Anyway", so the ad-hoc signature is renewed here.
seal_adhoc() {
  [ -n "$MACOS_SIGN_IDENTITY" ] && return 0
  echo "=== Re-sealing the ad-hoc signature after bundling ==="
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
  codesign --verify --deep --strict "$APP_BUNDLE"
}

codesign_app() {
  if [ -z "$MACOS_SIGN_IDENTITY" ]; then
    echo "=== Skipping code signing: MACOS_SIGN_IDENTITY not set ==="
    return 0
  fi
  if [ ! -f "$ENTITLEMENTS" ]; then
    echo "ERROR: entitlements not found at $ENTITLEMENTS" >&2
    return 1
  fi
  echo "=== Code signing $APP_BUNDLE with '$MACOS_SIGN_IDENTITY' ==="

  # Sign inner-most Mach-O binaries FIRST, then the outer .app. Do NOT use
  # --deep on the final app: it does not apply per-binary entitlements and
  # Apple discourages it. Every executable gets Hardened Runtime.
  local sign=(codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" --sign "$MACOS_SIGN_IDENTITY")

  # Bundled backend Mach-O (frozen interpreter, .so/.dylib extensions).
  if [ -d "$BACKEND_DEST" ]; then
    echo "--- Signing bundled backend Mach-O binaries ---"
    while IFS= read -r -d '' f; do
      file "$f" | grep -q 'Mach-O' && "${sign[@]}" "$f"
    done < <(find "$BACKEND_DEST" -type f \( -perm -111 -o -name '*.dylib' -o -name '*.so' \) -print0)
  fi

  # Nested frameworks + dylibs.
  local fw_dir="$APP_BUNDLE/Contents/Frameworks"
  if [ -d "$fw_dir" ]; then
    echo "--- Signing nested dylibs and executables ---"
    while IFS= read -r -d '' f; do
      file "$f" | grep -q 'Mach-O' && "${sign[@]}" "$f"
    done < <(find "$fw_dir" -type f \( -name '*.dylib' -o -perm -111 \) -print0)
    echo "--- Signing frameworks ---"
    while IFS= read -r -d '' fw; do
      "${sign[@]}" "$fw"
    done < <(find "$fw_dir" -type d -name '*.framework' -print0)
  fi

  # Any XPC / helper .app bundles inside Contents.
  while IFS= read -r -d '' helper; do
    [ "$helper" = "$APP_BUNDLE" ] && continue
    "${sign[@]}" "$helper"
  done < <(find "$APP_BUNDLE/Contents" -type d \( -name '*.app' -o -name '*.xpc' \) -print0)

  # Sign the outer .app LAST — this seals everything above.
  echo "--- Signing outer app bundle ---"
  "${sign[@]}" "$APP_BUNDLE"

  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  codesign --display --verbose=4 "$APP_BUNDLE" 2>&1 | grep -i 'flags\|runtime' || true
  echo "=== Code signing complete ==="
}

notarize_app() {
  [ -z "$MACOS_SIGN_IDENTITY" ] && return 0   # nothing signed → nothing to notarize

  local have_profile=0 have_creds=0
  [ -n "$MACOS_NOTARY_PROFILE" ] && have_profile=1
  { [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_PASSWORD" ]; } && have_creds=1

  if [ "$have_profile" -eq 0 ] && [ "$have_creds" -eq 0 ]; then
    echo "=== Skipping notarization: set MACOS_NOTARY_PROFILE, or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD ==="
    return 0
  fi

  # notarytool needs a zip/dmg/pkg. ditto preserves symlinks/xattrs (plain zip
  # corrupts frameworks).
  local zip_path="$PROJECT_DIR/build/macos/$PRODUCT_NAME-notarize.zip"
  echo "=== Zipping for notarization ==="
  rm -f "$zip_path"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$zip_path"

  echo "=== Submitting to Apple notary service (can take minutes) ==="
  if [ "$have_profile" -eq 1 ]; then
    xcrun notarytool submit "$zip_path" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$zip_path" \
      --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
  fi

  echo "=== Stapling notarization ticket ==="
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  /usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE" || true
  rm -f "$zip_path"
  echo "=== Notarization complete ==="
}

seal_adhoc
codesign_app
notarize_app

echo "=== Build complete: $VERSION_NAME Build $BUILD_NUM ==="
echo "Output: build/macos/Build/Products/Release/"
