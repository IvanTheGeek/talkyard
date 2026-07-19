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

echo "=== images + compile (big heap — a cold clone full-compiles; compose's
# default 2800 MB heap GC-thrashes on that, so use the s/d-cli path which
# floors the heap) ==="
b/build --isolated bash -c 'sudo docker compose build nodejs app rendr cache rdb search egressp' \
  > "$logs/stack-up.log" 2>&1
TY_BUILD_HEAP_MB=6144 b/build --isolated bash -c 's/d-cli compile < /dev/null' \
  > "$logs/compile.log" 2>&1 || { echo "compile FAILED:"; tail -20 "$logs/compile.log"; exit 1; }

echo "=== debug asset bundles (gulp in container — /-/are-scripts-ready checks
# for these; a fresh clone has none, so the ready-wait can never succeed
# without this step, and the browsers need the bundles anyway) ==="
b/build --isolated bash -c 'make debug_asset_bundles' \
  > "$logs/bundles.log" 2>&1 || { echo "bundles FAILED:"; tail -20 "$logs/bundles.log"; exit 1; }

echo "=== stack up (isolated dind) ==="
b/build --isolated bash -c 'sudo docker compose up -d' \
  >> "$logs/stack-up.log" 2>&1

echo "=== waiting for server (cold CI clone = full dev-mode compile, can take 30+ min) ==="
ready=""
for i in $(seq 1 480); do
  if docker exec "$TY_DIND_NAME" wget -q -O /dev/null http://localhost/-/are-scripts-ready 2>/dev/null; then
    ready=1; echo "server ready (~$(( i * 5 ))s)"; break
  fi
  [ $(( i % 24 )) -eq 0 ] && echo "  still compiling/starting (~$(( i * 5 / 60 )) min)"
  sleep 5
done
if [ -z "$ready" ]; then
  echo "server never became ready; app container log tail:"
  docker exec "$TY_DIND_NAME" docker logs --tail 40 tyd1-app-1 2>&1 | tail -40
  exit 1
fi

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
