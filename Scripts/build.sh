#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# LeanMac build script.
#
#   Scripts/build.sh              build, sign, install to /Applications and launch
#   Scripts/build.sh --no-run     build and package build/LeanMac.app only
#   Scripts/build.sh --dev        contributor mode: build, ad-hoc sign if there is no signing
#                                 identity, and launch from build/ in read-only hardware mode
#                                 (LEANMAC_DEV=1: no SMC writes, no privileged helper needed)
#   Scripts/build.sh --universal  also build for Intel (arm64 + x86_64)
#
# Signing identity: $LEANMAC_SIGN_IDENTITY (default "JMac Self-Signed", created once by
# Scripts/setup-signing-identity.sh). Ad-hoc signing changes the code hash on every build, so
# macOS revokes the Accessibility permission each time; a fixed identity keeps it.
set -e

cd "$(dirname "$0")/.."

APP_NAME="LeanMac"
BUNDLE_ID="com.local.jmac"   # Do not change: it would reset every permission users already granted.
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
BUNDLE_SRC="App/Bundle"

NO_RUN=false
DEV=false
UNIVERSAL=false
for arg in "$@"; do
    case "$arg" in
        --no-run) NO_RUN=true ;;
        --dev) DEV=true; NO_RUN=true ;;
        --universal) UNIVERSAL=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
[ "$CI" = "true" ] && NO_RUN=true

echo ""
echo "LeanMac build"
echo ""

# ── Step 0: stop running instances (installed run only) ──
if [ "$NO_RUN" = "false" ]; then
    pkill -x "${APP_NAME}" 2>/dev/null || true
    sleep 0.5
fi

# ── Step 1: compile ──
if [ "$UNIVERSAL" = "true" ]; then
    echo "Building ${APP_NAME} (release, universal: arm64 + x86_64)..."
    mkdir -p .build/bin_arm64 .build/bin_x86_64 .build/release
    swift build -c release --triple arm64-apple-macosx
    cp "$(swift build -c release --triple arm64-apple-macosx --show-bin-path)/${APP_NAME}" .build/bin_arm64/
    swift build -c release --triple x86_64-apple-macosx
    cp "$(swift build -c release --triple x86_64-apple-macosx --show-bin-path)/${APP_NAME}" .build/bin_x86_64/
    BINARY=".build/release/${APP_NAME}"
    lipo -create .build/bin_arm64/${APP_NAME} .build/bin_x86_64/${APP_NAME} -output "$BINARY"
else
    echo "Building ${APP_NAME} (release, Apple Silicon)..."
    swift build -c release
    BINARY="$(swift build -c release --show-bin-path)/${APP_NAME}"
fi

if [ ! -f "$BINARY" ]; then
    echo "Build failed: binary not found." >&2
    exit 1
fi
echo "Built: $(file "$BINARY")"

# ── Step 2: assemble the .app bundle ──
echo "Packaging app bundle..."
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"
cp "$BINARY" "${MACOS}/"

cp "${BUNDLE_SRC}/Info.plist" "${CONTENTS}/Info.plist"
cp "${BUNDLE_SRC}/AppIcon.icns" "${RESOURCES}/"
# Privileged-helper files are copied flat: the app finds them with Bundle.main.path(forResource:).
cp "${BUNDLE_SRC}/Helper/"* "${RESOURCES}/"
chmod +x "${RESOURCES}/smc" "${RESOURCES}/leanmac-power" "${RESOURCES}/install-helper.sh"
# Translations: <code>.lproj folders (see App/Bundle/Localization/README.md).
for lproj in "${BUNDLE_SRC}/Localization/"*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "${RESOURCES}/"
done
[ -f LICENSE ] && cp LICENSE "${RESOURCES}/LICENSE"

# ── Step 3: code sign ──
SIGN_IDENTITY="${LEANMAC_SIGN_IDENTITY:-${JMAC_SIGN_IDENTITY:-JMac Self-Signed}}"
SIGN_KEYCHAIN="${LEANMAC_SIGN_KEYCHAIN:-${JMAC_SIGN_KEYCHAIN:-}}"
FIND_ARGS=()
[ -n "${SIGN_KEYCHAIN}" ] && FIND_ARGS=("${SIGN_KEYCHAIN}")
# No -v: on CI runners a self-signed certificate is not trusted, so -v reports 0 identities
# even though codesign can still use it.
if security find-identity -p codesigning "${FIND_ARGS[@]}" 2>/dev/null | grep -qF "${SIGN_IDENTITY}"; then
    echo "Code signing (${SIGN_IDENTITY})..."
    CODESIGN_ARGS=(--force --deep --sign "${SIGN_IDENTITY}" --identifier "${BUNDLE_ID}")
    [ -n "${SIGN_KEYCHAIN}" ] && CODESIGN_ARGS+=(--keychain "${SIGN_KEYCHAIN}")
    codesign "${CODESIGN_ARGS[@]}" "${APP_DIR}"
else
    echo "Code signing (ad-hoc): the Accessibility permission will be lost after every build."
    echo "  Run Scripts/setup-signing-identity.sh once to avoid that."
    codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_DIR}" 2>/dev/null || true
fi

if [ "$DEV" = "true" ]; then
    echo "Built ${APP_DIR}. Launching in contributor mode (LEANMAC_DEV=1, read-only hardware)..."
    LEANMAC_DEV=1 "${MACOS}/${APP_NAME}"
    exit 0
fi

if [ "$NO_RUN" = "true" ]; then
    echo "Built ${APP_DIR}"
    exit 0
fi

# ── Step 4: install and launch ──
echo "Installing to /Applications/${APP_NAME}.app..."
sleep 0.3
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${APP_DIR}" "/Applications/${APP_NAME}.app"
echo "Launching..."
open "/Applications/${APP_NAME}.app"
sleep 1
PID=$(pgrep -x "${APP_NAME}" || true)
if [ -n "$PID" ]; then
    echo "${APP_NAME} is running (PID ${PID})."
else
    echo "${APP_NAME} not detected yet; check Console or ~/Library/Logs/LeanMac/leanmac.log." >&2
fi
