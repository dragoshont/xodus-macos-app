#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
python3 tools/sync_contract.py
swift build
swift run XodusFixtureChecks
swift run XodusManagementChecks
swift run XodusPreview --self-check
swift run XodusPreview --live-check
