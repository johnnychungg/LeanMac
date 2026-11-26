#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Fails when the layering rules in ARCHITECTURE.md are broken. Run it before every pull request:
#   Scripts/check-architecture.sh
set -u
cd "$(dirname "$0")/.."

ALLOW="Docs/architecture-allowlist.txt"
status=0

allowed() { # rule path
    grep -E "^$1[[:space:]]+$2([[:space:]]|\$)" "$ALLOW" >/dev/null 2>&1
}

fail() { echo "ARCHITECTURE: $*"; status=1; }

# files_matching <dir> <regex>: prints "file:line:text" for non-comment lines matching the regex
scan() {
    grep -rnE "$2" "$1" --include='*.swift' 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true
}

# --- 1. LeanDomain is pure: Foundation, CoreGraphics, Combine only; no process spawning -------------
while IFS= read -r hit; do
    [ -n "$hit" ] && fail "Domain must stay pure: $hit"
done < <(scan Sources/LeanDomain '^[[:space:]]*import[[:space:]]+(AppKit|SwiftUI|IOKit|UserNotifications|ServiceManagement|ApplicationServices|Carbon|ScreenCaptureKit|CoreBluetooth|LeanPlatform|LeanFeatures|LeanDesignSystem)')
while IFS= read -r hit; do
    [ -n "$hit" ] && fail "Domain must not spawn processes (use the ShellRunning port): $hit"
done < <(scan Sources/LeanDomain '(^|[^A-Za-z0-9_])Process\(\)|NSAppleScript|dlopen\(')

# --- 2. DesignSystem and Platform depend only downwards -------------------------------------------
while IFS= read -r hit; do
    [ -n "$hit" ] && fail "DesignSystem must not import Platform/Features: $hit"
done < <(scan Sources/LeanDesignSystem '^[[:space:]]*import[[:space:]]+(LeanPlatform|LeanFeatures)')
while IFS= read -r hit; do
    [ -n "$hit" ] && fail "Platform must not import DesignSystem/Features: $hit"
done < <(scan Sources/LeanPlatform '^[[:space:]]*import[[:space:]]+(LeanDesignSystem|LeanFeatures)')

# --- 3. LeanFeatures reaches the machine only through ports (allowlisted debt excepted) -----------
for rule_re in "features-import-platform|^[[:space:]]*import[[:space:]]+LeanPlatform" \
               "features-import-iokit|^[[:space:]]*import[[:space:]]+IOKit" \
               "features-use-process|(^|[^A-Za-z0-9_])Process\\(\\)|NSAppleScript"; do
    rule="${rule_re%%|*}"; re="${rule_re#*|}"
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        allowed "$rule" "$file" || fail "$file breaks '$rule' and is not in $ALLOW"
    done < <(scan Sources/LeanFeatures "$re" | cut -d: -f1 | sort -u)
done
# Allowlist entries must still be needed (so the debt list can only shrink).
while read -r rule path _; do
    case "$rule" in ''|\#*) continue ;; esac
    [ -f "$path" ] || { fail "allowlist entry points to a missing file: $path"; continue; }
    case "$rule" in
        features-import-platform) re='^[[:space:]]*import[[:space:]]+LeanPlatform' ;;
        features-import-iokit)    re='^[[:space:]]*import[[:space:]]+IOKit' ;;
        features-use-process)     re='(^|[^A-Za-z0-9_])Process\(\)|NSAppleScript' ;;
        *) fail "unknown allowlist rule: $rule"; continue ;;
    esac
    grep -qE "$re" "$path" || fail "stale allowlist entry (debt already paid, delete the line): $rule $path"
done < "$ALLOW"

# --- 4. sudo command lines are assembled in exactly one place -------------------------------------
while IFS= read -r hit; do
    [ -n "$hit" ] && fail "only PrivilegedHelper.sudoCommand may build sudo command lines: $hit"
done < <(scan Sources 'sudo -|"sudo|sudo \\\(' | grep -v 'Sources/LeanDomain/Helper/PrivilegedHelper.swift')
while IFS= read -r hit; do
    [ -n "$hit" ] && fail "sudo outside the helper module: $hit"
done < <(scan App 'sudo ')

# --- 5. Swift 5.9 toolchains must keep compiling ---------------------------------------------------
while IFS= read -r hit; do
    [ -n "$hit" ] && fail "nonisolated(unsafe) needs Swift 5.10; use a lock-protected box: $hit"
done < <(scan Sources 'nonisolated\(unsafe\)'; scan App 'nonisolated\(unsafe\)'; scan Tests 'nonisolated\(unsafe\)')

# --- 6. The privileged-helper install locations never change silently -----------------------------
grep -q '/Library/PrivilegedHelperTools/com.local.leanmac.power' Sources/LeanDomain/Helper/PrivilegedHelper.swift \
    || fail "helper install path changed"

if [ $status -eq 0 ]; then
    echo "Architecture check passed."
fi
exit $status
