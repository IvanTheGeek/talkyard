#!/bin/bash
# Nightly e2e: both suites against the dev stack, entirely inside the CI
# dind daemon (no host ports touched — devvps-caddy et al keep 80/443).
#
# Change guard: skips when HEAD == the marker from the last green run,
# unless TY_BASELINE=1 (set while collecting flake baselines) or the run
# was manually dispatched (TY_FORCE=1).
set -euo pipefail
. "$(dirname "$0")/env.sh"
cd "$TY_CI_REPO"

head="$(git rev-parse HEAD)"
marker="$TY_CI_STATE/last-e2e-green"
if [ -z "${TY_BASELINE:-}" ] && [ -z "${TY_FORCE:-}" ] \
   && [ -f "$marker" ] && [ "$(cat "$marker")" = "$head" ]; then
  echo "nightly-e2e: HEAD unchanged since last green run ($head) — skipping."
  exit 0
fi

logs="$(ci_log_dir)"
echo "nightly-e2e: logs -> $logs"

cleanup() {
  b/build --isolated bash -c 'sudo docker compose down' >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== stack up (isolated dind) ==="
b/build --isolated bash -c 'sudo docker compose build nodejs app rendr cache rdb search egressp && sudo docker compose up -d' \
  > "$logs/stack-up.log" 2>&1

echo "=== waiting for server (cold CI clone = full dev-mode compile, can take 30+ min) ==="
ready=""
for i in $(seq 1 480); do
  if docker exec "$TY_DIND_NAME" wget -q -O /dev/null http://localhost/-/are-scripts-ready 2>/dev/null; then
    ready=1; echo "server ready (~$(( i * 5 ))s)"; break
  fi
  [ $(( i % 24 )) -eq 0 ] && echo "  still compiling/starting (~$(( i * 5 / 60 )) min)"
  sleep 5
done
[ -z "$ready" ] && { echo "server never became ready"; tail -50 "$logs/stack-up.log"; exit 1; }

rc=0

echo "=== wdio7 ==="
if [ -n "${TY_BASELINE:-}" ]; then
  # Baseline period: run the FULL suite to (re)derive the green list.
  b/e2e --isolated > "$logs/wdio7-full.log" 2>&1 || rc=$?
else
  b/e2e --isolated --skip-expected-fails > "$logs/wdio7-gate.log" 2>&1 || rc=$?
fi
grep -E "e2e shard .* done|Spec Files:" "$logs"/wdio7-*.log | tail -3 || true

echo "=== wdio6 ==="
b/e2e6 --isolated > "$logs/wdio6-full.log" 2>&1 || rc=$?
grep -E "e2e6 shard .* done" "$logs/wdio6-full.log" | tail -1 || true

if [ $rc -eq 0 ]; then
  echo "$head" > "$marker"
  echo "nightly-e2e: GREEN — marker updated."
else
  echo "nightly-e2e: FAILURES (exit $rc) — see $logs; marker NOT updated."
fi
exit $rc
