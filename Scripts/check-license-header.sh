#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Every source file carries "SPDX-License-Identifier: GPL-3.0-only" in its first lines.
#   Scripts/check-license-header.sh
set -u
cd "$(dirname "$0")/.."
status=0
while IFS= read -r file; do
    if ! head -n 4 "$file" | grep -q 'SPDX-License-Identifier: GPL-3.0-only'; then
        echo "LICENSE: missing SPDX header: $file"
        status=1
    fi
done < <(find Sources App Tests Scripts -type f \( -name '*.swift' -o -name '*.sh' -o -name '*.py' -o -name 'leanmac-power' \) | sort; echo Package.swift; echo build.sh)
[ $status -eq 0 ] && echo "License headers present."
exit $status
