#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Tests the argument validation of the privileged helper scripts WITHOUT root and without touching the
# SMC: it extracts the validation code from the real scripts and feeds it hostile input.
#   Scripts/test-helper.sh
set -u
cd "$(dirname "$0")/.."

HELPER="App/Bundle/Helper/leanmac-power"
INSTALL="App/Bundle/Helper/install-helper.sh"
fails=0
checks=0

ok()   { checks=$((checks + 1)); }
bad()  { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL: $*"; }

# --- valid_limit(): only integers 20..100 -----------------------------------------------------------
eval "$(sed -n '/^valid_limit()/,/^}/p' "$HELPER")"

for v in 20 21 50 80 99 100; do valid_limit "$v" && ok || bad "valid_limit rejected $v"; done
for v in "" 0 19 101 1000 -5 +50 5.5 " 50" "50 " "a" "50;id" '$(id)' 'a[$(id)]' '`id`' "50&&id" "50|id" "1e2" "0x50" "08" ; do
    case "$v" in 08) continue ;; esac   # leading zero is plain decimal 8 -> below 20, covered below
    if valid_limit "$v"; then bad "valid_limit accepted '$v'"; else ok; fi
done
valid_limit 08 && bad "valid_limit accepted 08" || ok

# --- user name rule of install-helper.sh --------------------------------------------------------------
rule=$(sed -n '/^case "\$TARGET_USER" in/,/^esac/p' "$INSTALL")
[ -n "$rule" ] || { echo "FAIL: user-name rule not found in install-helper.sh"; exit 1; }
user_ok() {
    TARGET_USER="$1"
    # the rule runs `exit 1` on rejection: run it in a subshell
    ( eval "$rule" ) >/dev/null 2>&1
}
for u in johnny alice_01 a.b-c Z9; do user_ok "$u" && ok || bad "user rule rejected $u"; done
for u in root ALL . .. -x "a b" 'a;b' 'a$(id)' "a'b" 'a"b' 'a\b' 'a/b' 'a*b' 'a,b' 'a:b' "a=b" "$(printf 'a\nb')"; do
    if user_ok "$u"; then bad "user rule accepted '$u'"; else ok; fi
done

# --- structural guarantees ------------------------------------------------------------------------------
grep -q '^export PATH=/usr/bin:/bin:/usr/sbin:/sbin' "$HELPER" && ok || bad "helper must reset PATH"
grep -q 'stat -f %u "\$SMC"' "$HELPER" && ok || bad "helper must require a root-owned smc"
grep -q '\[ -L "\$SMC" \]' "$HELPER" && ok || bad "helper must refuse a symlinked smc"
grep -q '\[ -z "\$TARGET_USER" \]' "$INSTALL" && ok || bad "installer must reject an empty user"
grep -q 'visudo -cf' "$INSTALL" && ok || bad "installer must validate the sudoers rule with visudo"
grep -q 'NOPASSWD: \$POWER' "$INSTALL" && ok || bad "sudoers rule must name exactly the helper"
grep -q 'install -o root -g wheel -m 440' "$INSTALL" && ok || bad "sudoers file must be root:wheel 440"
grep -q 'stat -f %u' "$INSTALL" && ok || bad "installer must require root-owned sources"
INSTALLER_SWIFT="Sources/LeanPlatform/Battery/HelperInstaller.swift"
BUILDER_SWIFT="Sources/LeanDomain/Helper/HelperInstallCommand.swift"
grep -q 'mktemp -d /private/tmp/leanmac.XXXXXX' "$BUILDER_SWIFT" && ok || bad "root temp dir must use an explicit /private/tmp template"
if grep -q 'TMPDIR' "$BUILDER_SWIFT" "$INSTALLER_SWIFT"; then bad "installer must not rely on TMPDIR"; else ok; fi
grep -q '^export TMPDIR=/private/tmp' "$INSTALL" && ok || bad "install-helper.sh must pin TMPDIR"
grep -q 'mktemp "\$DIR/' "$INSTALL" && ok || bad "sudoers temp file must live in the root-owned helper dir"
grep -q 'base64 -D' "$BUILDER_SWIFT" && ok || bad "payload must travel inline (base64)"
# every verb that takes a limit validates it
for verb in charge-off charge-on watchdog; do
    awk -v v="$verb" '$0 ~ "^    " v "\\)" {f=1} f && /valid_limit/ {found=1} END {exit !found}' "$HELPER" \
        && ok || bad "verb $verb does not call valid_limit"
done
# the helper must not evaluate its arguments
if grep -nE '(^|[^a-z])eval[[:space:]]' "$HELPER" | grep -v '^[0-9]*:[[:space:]]*#'; then bad "helper uses eval"; else ok; fi

echo "$checks checks, $fails failed"
[ "$fails" -eq 0 ]
