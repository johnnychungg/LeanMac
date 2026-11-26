#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Convenience wrapper: the real script lives in Scripts/build.sh.
exec "$(dirname "$0")/Scripts/build.sh" "$@"
