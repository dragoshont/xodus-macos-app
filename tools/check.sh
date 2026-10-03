#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
swift build
swift run XodusFixtureChecks
swift run XodusPreview --self-check
