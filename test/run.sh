#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KAMAL_CLI_TEST_DIR
KAMAL_CLI_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$KAMAL_CLI_TEST_DIR"' EXIT
export KAMAL_CLI_BUNDLE="$ROOT/test/bin/bundle"
export KAMAL_CLI_SOC2_EVENT="$ROOT/test/bin/soc2-event"
export KAMAL_CLI_KEEP_LOG_DIR="$KAMAL_CLI_TEST_DIR/kept-logs"
unset KAMAL_APPROVAL_REF KAMAL_CLI_REGISTRY_LOGOUT
export KAMAL_CLI_TEST_OTHER_KAMAL=0
chmod +x "$ROOT/test/bin/bundle" "$ROOT/test/bin/soc2-event" "$ROOT/kamal-cli"
ruby "$ROOT/test/test_runner.rb"
echo OK
