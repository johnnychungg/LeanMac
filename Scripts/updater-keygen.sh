#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Creates the Ed25519 key that signs update manifests. Run it ONCE, on the maintainer's Mac.
#   - The private key is stored in your login keychain (service "LeanMac updater signing key").
#     It is never printed and never written inside the repository.
#   - The script prints the PUBLIC key; paste it into `UpdateConfig.publicKeyBase64`
#     (Sources/LeanDomain/Update/UpdateManifest.swift) and commit that change.
#   - Back the key up (Keychain Access > export). If it is lost, installed apps can never verify a new
#     release again, and users would have to reinstall by hand.
set -euo pipefail

SERVICE="LeanMac updater signing key"

OPENSSL=""
for c in /opt/homebrew/bin/openssl /usr/local/bin/openssl; do
    if [ -x "$c" ] && "$c" pkeyutl -help 2>&1 | grep -q -- '-rawin'; then OPENSSL="$c"; break; fi
done
[ -n "$OPENSSL" ] || { echo "OpenSSL 3 is required (brew install openssl); the system LibreSSL cannot sign Ed25519." >&2; exit 1; }

umask 077
WORK="$(mktemp -d "${TMPDIR:-/tmp}/leanmac-keygen.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if security find-generic-password -s "$SERVICE" -a "$USER" >/dev/null 2>&1; then
    echo "A key already exists in your keychain; showing its public key (nothing was changed)."
    security find-generic-password -s "$SERVICE" -a "$USER" -w | base64 -D > "$WORK/key.pem"
else
    "$OPENSSL" genpkey -algorithm ed25519 -out "$WORK/key.pem"
    security add-generic-password -s "$SERVICE" -a "$USER" -w "$(base64 < "$WORK/key.pem" | tr -d '\n')" -U
    echo "New key stored in your login keychain."
fi

PUBLIC="$("$OPENSSL" pkey -in "$WORK/key.pem" -pubout -outform DER | tail -c 32 | base64)"
echo ""
echo "Public key (paste into UpdateConfig.publicKeyBase64):"
echo "$PUBLIC"
