#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KAMAL_CLI_TEST_DIR
KAMAL_CLI_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$KAMAL_CLI_TEST_DIR"' EXIT
export KAMAL_CLI_BUNDLE="$ROOT/test/bin/bundle"
chmod +x "$ROOT/test/bin/bundle" "$ROOT/kamal-cli"
ruby "$ROOT/test/test_runner.rb"
echo OK
