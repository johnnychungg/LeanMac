#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# ─────────────────────────────────────────────────────────────
#  setup-signing-identity.sh
#
#  Creates a FIXED self-signed code-signing identity for local LeanMac builds.
#
#  Why: an ad-hoc signature (`codesign -s -`) gets a new cdhash on EVERY build, so macOS treats each
#  build as a different app and revokes the Accessibility permission (the keyboard shortcuts stop
#  working until it is granted again by hand). Signing with one stable identity keeps the Designated
#  Requirement, so the permission survives rebuilds.
#
#  Run once:  Scripts/setup-signing-identity.sh
#  Afterwards Scripts/build.sh uses the identity automatically.
#
#  Override the name with LEANMAC_SIGN_IDENTITY (the same variable build.sh reads).
#  The private key only exists in a temporary folder that is deleted when the script ends;
#  after the import it lives only in your login keychain.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# macOS ships LibreSSL only (no -legacy). Prefer Homebrew's OpenSSL 3.
OPENSSL=""
for c in /opt/homebrew/bin/openssl /usr/local/bin/openssl /usr/bin/openssl; do
    if [ -x "$c" ] && "$c" pkcs12 -help 2>&1 | grep -q -- '-legacy'; then OPENSSL="$c"; break; fi
done
if [ -z "$OPENSSL" ]; then
    echo "OpenSSL 3 (with -legacy support) is required: brew install openssl" >&2
    exit 1
fi

IDENTITY_NAME="${LEANMAC_SIGN_IDENTITY:-JMac Self-Signed}"
case "$IDENTITY_NAME" in
    *[!A-Za-z0-9\ ._-]*|'') echo "Identity name may only contain letters, digits, space, '.', '_' and '-'." >&2; exit 1 ;;
esac
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

echo ""
echo "LeanMac: create a stable local signing identity"
echo ""

# ── 1. Already there? ──
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "${IDENTITY_NAME}"; then
    echo "Identity already exists: ${IDENTITY_NAME}"
    echo "Nothing to do."
    exit 0
fi

# ── 2. Generate key + self-signed certificate (codeSigning EKU) in a private temp folder ──
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leanmac-signing.XXXXXX")"
chmod 700 "${WORK_DIR}"
trap 'rm -rf "${WORK_DIR}"' EXIT
P12_PASS="$("${OPENSSL}" rand -hex 16)"

echo "Creating key and self-signed certificate..."

cat > "${WORK_DIR}/codesign.cnf" <<CNF
[req]
prompt             = no
distinguished_name = dn
x509_extensions    = v3_codesign
[dn]
CN = ${IDENTITY_NAME}
O  = LeanMac Local Signing
[v3_codesign]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
CNF

"${OPENSSL}" req -x509 -newkey rsa:2048 -nodes \
    -keyout "${WORK_DIR}/key.pem" \
    -out "${WORK_DIR}/cert.pem" \
    -days 3650 \
    -config "${WORK_DIR}/codesign.cnf" >/dev/null 2>&1

"${OPENSSL}" pkcs12 -export -legacy \
    -inkey "${WORK_DIR}/key.pem" \
    -in "${WORK_DIR}/cert.pem" \
    -name "${IDENTITY_NAME}" \
    -out "${WORK_DIR}/identity.p12" \
    -passout "pass:${P12_PASS}" >/dev/null 2>&1

# ── 3. Import into the login keychain; allow only codesign/security to use the key ──
echo "Importing into the login keychain..."
security import "${WORK_DIR}/identity.p12" \
    -k "${LOGIN_KEYCHAIN}" \
    -P "${P12_PASS}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

# macOS may still ask "codesign wants to sign..." the first time: choose Always Allow.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" "${LOGIN_KEYCHAIN}" >/dev/null 2>&1 || true

# ── 4. Trust it for code signing (user domain, no sudo) ──
# Without trust the identity still signs but is reported as CSSMERR_TP_NOT_TRUSTED.
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "${IDENTITY_NAME}"; then
    echo "Adding trust for the certificate (policy: Code Signing)..."
    security add-trusted-cert -r trustRoot -p codeSign \
        -k "${LOGIN_KEYCHAIN}" "${WORK_DIR}/cert.pem" >/dev/null 2>&1 || true
fi

# ── 5. Verify ──
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "${IDENTITY_NAME}"; then
    echo ""
    echo "Done. The identity is ready:"
    security find-identity -v -p codesigning | grep -F "${IDENTITY_NAME}"
    echo ""
    echo "The temporary key files were deleted; the key now lives only in your login keychain."
    echo "Next: Scripts/build.sh. Grant Accessibility once; it is kept across rebuilds."
else
    echo "Could not create the identity. Check your login keychain." >&2
    exit 1
fi
