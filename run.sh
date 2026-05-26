#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
exec .build/release/Lights
