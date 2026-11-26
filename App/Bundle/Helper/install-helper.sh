#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Installs the charge-lock helper. Runs as root through "do shell script ... with administrator privileges".
#   $1 = smc   $2 = leanmac-power   $3 = user allowed to run the helper
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
# Never trust the caller's TMPDIR (a user-owned parent lets the user swap temp files).
export TMPDIR=/private/tmp

SRC_SMC="${1:-}"
SRC_HELPER="${2:-}"
TARGET_USER="${3:-}"

DIR=/Library/PrivilegedHelperTools
POWER="$DIR/com.local.leanmac.power"
SMC="$DIR/com.local.leanmac.smc"
SUDOERS=/etc/sudoers.d/leanmac_power

if [ -z "$SRC_SMC" ] || [ -z "$SRC_HELPER" ] || [ -z "$TARGET_USER" ]; then
    echo "Error: Missing arguments"
    exit 1
fi

# Defense in depth: the sources must be regular files owned by root and not writable by group/others
# (the app delivers them into a root-owned mktemp -d directory; see HelperInstallCommand).
for f in "$SRC_SMC" "$SRC_HELPER"; do
    if [ ! -f "$f" ] || [ -L "$f" ] || [ "$(stat -f %u "$f")" != "0" ]; then
        echo "Error: Invalid source files"
        exit 1
    fi
    case "$(stat -f %Sp "$f")" in
        ?????w*|????????w*) echo "Error: source files must not be group/world writable"; exit 1 ;;
    esac
done

# The user name goes into the sudoers rule: only safe characters, no special keywords, and nothing starting with '-'.
case "$TARGET_USER" in
    *[!A-Za-z0-9._-]*|-*|.|..|ALL|root) echo "Error: invalid user name"; exit 1 ;;
esac
id -u "$TARGET_USER" >/dev/null 2>&1 || { echo "Error: unknown user"; exit 1; }

mkdir -p "$DIR" /etc/sudoers.d
chown root:wheel "$DIR"
chmod 755 "$DIR"

install -o root -g wheel -m 755 "$SRC_SMC" "$SMC"
install -o root -g wheel -m 755 "$SRC_HELPER" "$POWER"

# Only the installing user, only this helper. The helper validates every argument itself before acting.
TMP=$(mktemp "$DIR/.sudoers.XXXXXX")
trap 'rm -f "$TMP"' EXIT
echo "$TARGET_USER ALL=(root) NOPASSWD: $POWER" > "$TMP"
visudo -cf "$TMP" >/dev/null
install -o root -g wheel -m 440 "$TMP" "$SUDOERS"

echo "SUCCESS"
