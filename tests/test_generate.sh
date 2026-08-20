#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/createDaemonService.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: expected to find: $needle" >&2
    fail=1
  fi
}

assert_missing() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: did not expect: $needle" >&2
    fail=1
  fi
}

assert_exit() {
  local expected="$1"
  shift
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    echo "FAIL: exit $status, expected $expected: $*" >&2
    fail=1
  fi
}

bash -n "$SCRIPT"

unit="$("$SCRIPT" --dry-run --name realichaind --exec /usr/local/bin/realichaind --user realichain --datadir /var/lib/realichain --conf /etc/realichain.conf --args "-printtoconsole")"
assert_contains "$unit" "ExecStart=/usr/local/bin/realichaind -printtoconsole -conf=/etc/realichain.conf -datadir=/var/lib/realichain"
assert_contains "$unit" "User=realichain"
assert_contains "$unit" "Group=realichain"
assert_contains "$unit" "Type=simple"
assert_contains "$unit" "After=network-online.target"
assert_contains "$unit" "LimitNOFILE=65535"
assert_contains "$unit" "PrivateTmp=true"
assert_contains "$unit" "Description=Realichain daemon"
assert_missing "$unit" "MemoryDenyWriteExecute=true"
assert_missing "$unit" "PIDFile="

hardened="$("$SCRIPT" --dry-run --name appd --exec /bin/true --harden)"
assert_contains "$hardened" "MemoryDenyWriteExecute=true"
assert_contains "$hardened" "ProtectSystem=full"

forking="$("$SCRIPT" --dry-run --name bitcoind --exec /usr/bin/bitcoind --type forking --user bitcoin)"
assert_contains "$forking" "Type=forking"
assert_contains "$forking" "PIDFile=/run/bitcoind.pid"

quoted="$("$SCRIPT" --dry-run --name web --exec "/tmp/bin with space" --args "--port 8080")"
assert_contains "$quoted" 'ExecStart="/tmp/bin with space" --port 8080'

out="$TMP/demo.service"
"$SCRIPT" --name demo --exec /bin/true --output "$out" --no-enable --force >/dev/null
[[ -f "$out" ]] || { echo "FAIL: --output did not write $out" >&2; fail=1; }
assert_contains "$(cat "$out")" "ExecStart=/bin/true"

assert_exit 1 "$SCRIPT" --dry-run --name "bad name" --exec /bin/true
assert_exit 1 "$SCRIPT" --dry-run --exec /bin/true
assert_exit 1 "$SCRIPT" --dry-run --name ok
assert_exit 0 "$SCRIPT" --help

if [[ "$fail" -ne 0 ]]; then
  echo "Some tests failed"
  exit 1
fi
echo "All tests passed"
