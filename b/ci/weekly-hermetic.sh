#!/bin/bash
# Weekly hermetic proof: warm the CI dind cache online, then run a full
# CLEAN build + test with zero network (offline dind, same cache volume).
# Change-guarded like nightly-e2e (TY_FORCE=1 to override).
set -euo pipefail
. "$(dirname "$0")/env.sh"
cd "$TY_CI_REPO"

head="$(git rev-parse HEAD)"
marker="$TY_CI_STATE/last-hermetic-green"
if [ -z "${TY_FORCE:-}" ] && [ -f "$marker" ] && [ "$(cat "$marker")" = "$head" ]; then
  echo "weekly-hermetic: HEAD unchanged since last green run — skipping."
  exit 0
fi

logs="$(ci_log_dir)"

echo "=== phase 1: warm image cache (online dind) ==="
b/build --isolated bash -c 'sudo docker compose build nodejs app rendr cache rdb search egressp' \
  > "$logs/hermetic-warm.log" 2>&1

echo "=== phase 2: full-clean build + test, OFFLINE ==="
TY_DIND_OFFLINE=1 b/build --isolated bash -c \
  'make clean_bundles && sudo PLAY_HEAP_MEMORY_MB=6144 s/d-cli clean < /dev/null && b/check' \
  > "$logs/hermetic-check.log" 2>&1
rc=$?

tail -8 "$logs/hermetic-check.log"
if [ $rc -eq 0 ]; then
  echo "$head" > "$marker"
  echo "weekly-hermetic: GREEN (offline full-clean build+test passed)."
else
  echo "weekly-hermetic: FAILED (exit $rc) — vendored inputs may be incomplete; see $logs."
fi
exit $rc
