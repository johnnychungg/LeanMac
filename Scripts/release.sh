#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Prepares a release: bumps the version, builds and signs the app, zips it, and writes the signed update manifest.
#   Scripts/release.sh 1.1.0
# It never commits, tags or publishes anything: it prints the commands for that at the end.
#
# Requirements: the maintainer's fixed signing identity (Scripts/setup-signing-identity.sh, never ad-hoc),
# the updater key (Scripts/updater-keygen.sh) and its public key committed in UpdateConfig.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: Scripts/release.sh MAJOR.MINOR.PATCH" >&2; exit 1; }

PLIST="App/Bundle/Info.plist"
OWNER_REPO="johnnychungg/LeanMac"
SERVICE="LeanMac updater signing key"
CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "CFBundleVersion must be an integer build number, found '$BUILD'." >&2; exit 1; }

# Version must go up.
newer() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ] && [ "$1" != "$2" ]; }
newer "$VERSION" "$CURRENT" || { echo "Version $VERSION must be greater than the current $CURRENT." >&2; exit 1; }

[ -z "$(git status --porcelain)" ] || { echo "The working tree must be clean before a release." >&2; exit 1; }
grep -Eq 'publicKeyBase64 = "[A-Za-z0-9+/=]{44}"' Sources/LeanDomain/Update/UpdateManifest.swift \
    || { echo "UpdateConfig.publicKeyBase64 is empty: run Scripts/updater-keygen.sh and commit the key first." >&2; exit 1; }

OPENSSL=""
for c in /opt/homebrew/bin/openssl /usr/local/bin/openssl; do
    if [ -x "$c" ] && "$c" pkeyutl -help 2>&1 | grep -q -- '-rawin'; then OPENSSL="$c"; break; fi
done
[ -n "$OPENSSL" ] || { echo "OpenSSL 3 is required (brew install openssl)." >&2; exit 1; }

# Run the gates first.
Scripts/check-architecture.sh
python3 Scripts/check-l10n.py
Scripts/check-license-header.sh
Scripts/test-helper.sh
swift test

# Bump versions (the plist is the single source of truth).
NEW_BUILD=$((BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"

# Changelog: commit subjects since the last tag.
LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
RANGE="${LAST_TAG:+$LAST_TAG..}HEAD"
NOTES="$(mktemp "${TMPDIR:-/tmp}/leanmac-changelog.XXXXXX")"
{
    echo "## $VERSION - $(date +%Y-%m-%d)"
    echo ""
    git log --no-merges --format='- %s' $RANGE
    echo ""
} > "$NOTES"
if [ -f Docs/CHANGELOG.md ]; then
    { head -2 Docs/CHANGELOG.md; cat "$NOTES"; tail -n +3 Docs/CHANGELOG.md; } > Docs/CHANGELOG.md.tmp
else
    { echo "# Changelog"; echo ""; cat "$NOTES"; } > Docs/CHANGELOG.md.tmp
fi
mv Docs/CHANGELOG.md.tmp Docs/CHANGELOG.md
rm -f "$NOTES"

# Build with the real identity; an ad-hoc signature would make every update fail its identity check.
Scripts/build.sh --no-run
if codesign -dvv build/LeanMac.app 2>&1 | grep -q 'Signature=adhoc'; then
    echo "The app is signed ad-hoc. Run Scripts/setup-signing-identity.sh and build again." >&2
    exit 1
fi

mkdir -p dist
ZIP="dist/LeanMac-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/LeanMac.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
MINOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"

cat > dist/update.json <<JSON
{"version":"$VERSION","build":$NEW_BUILD,"minimumSystemVersion":"$MINOS","url":"https://github.com/$OWNER_REPO/releases/download/v$VERSION/LeanMac-$VERSION.zip","sha256":"$SHA","notesURL":"https://github.com/$OWNER_REPO/releases/tag/v$VERSION"}
JSON

# Sign the manifest with the key from the keychain (it lives in a 0600 temp file only while signing).
umask 077
WORK="$(mktemp -d "${TMPDIR:-/tmp}/leanmac-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
security find-generic-password -s "$SERVICE" -a "$USER" -w | base64 -D > "$WORK/key.pem"
"$OPENSSL" pkeyutl -sign -rawin -inkey "$WORK/key.pem" -in dist/update.json -out "$WORK/sig.bin"
base64 < "$WORK/sig.bin" | tr -d '\n' > dist/update.json.sig
"$OPENSSL" pkey -in "$WORK/key.pem" -pubout -out "$WORK/pub.pem"
"$OPENSSL" pkeyutl -verify -rawin -pubin -inkey "$WORK/pub.pem" -in dist/update.json -sigfile "$WORK/sig.bin" >/dev/null

echo ""
echo "Release $VERSION (build $NEW_BUILD) is ready in dist/:"
ls -l dist/LeanMac-"$VERSION".zip dist/update.json dist/update.json.sig
echo ""
echo "Next steps (nothing has been committed or published):"
echo "  1. Review Docs/CHANGELOG.md and the plist bump, then:"
echo "       git add -A && git commit -m \"Release $VERSION\" && git tag -a v$VERSION -m \"LeanMac $VERSION\""
echo "  2. git push origin main v$VERSION"
echo "  3. Publish with the three files in dist/ (the app looks for update.json and update.json.sig):"
echo "       gh release create v$VERSION dist/LeanMac-$VERSION.zip dist/update.json dist/update.json.sig --title \"LeanMac $VERSION\" --notes-file Docs/CHANGELOG.md"
