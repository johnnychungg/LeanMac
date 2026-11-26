#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Builds the `smc` tool from the vendored upstream sources (ThirdParty/smc) into build/smc.
# This is optional: the repository already ships a prebuilt binary in App/Bundle/Helper/smc.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
clang -O2 -arch arm64 -DCMD_TOOL_BUILD -o build/smc ThirdParty/smc/smc.c -framework IOKit -framework CoreFoundation
echo "Built build/smc"
shasum -a 256 build/smc
