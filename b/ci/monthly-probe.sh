#!/bin/bash
# Monthly availability probe: the repo may be unchanged while the WORLD
# moves — verify every pinned external input is still fetchable. Runs
# regardless of code changes (that's its point). Cheap: registry metadata
# lookups, no big downloads.
set -euo pipefail
. "$(dirname "$0")/env.sh"
cd "$TY_CI_REPO"

fail=0

echo "=== digest-pin guard ==="
b/pin-digests --check || fail=1

echo "=== pinned base images still resolvable ==="
refs=$(grep -hE '^FROM [^ ]+@sha256:' images/*/Dockerfile* | awk '{print $2}' | sort -u;
       sed -n 's/^TY_DIND_IMAGE=\(.*\)$/\1/p' b/impl/dind-lib.sh)
for ref in $refs; do
  if docker buildx imagetools inspect "$ref" >/dev/null 2>&1; then
    echo "ok    $ref"
  else
    echo "GONE  $ref"; fail=1
  fi
done

echo "=== npm registry + fibers prebuilt reachable ==="
curl -fsS -o /dev/null https://registry.npmjs.org/fibers && echo "ok    registry.npmjs.org" || { echo "FAIL  npm registry"; fail=1; }
curl -fsSI -o /dev/null https://github.com/laverdet/node-fibers/releases && echo "ok    fibers releases" || { echo "FAIL  fibers releases"; fail=1; }

echo "=== crates.io (sqlx-cli 0.8.6) reachable ==="
curl -fsS -A 'ty-build-monthly-probe (forgejo.ivanthegeek.com)' -o /dev/null https://crates.io/api/v1/crates/sqlx-cli/0.8.6 && echo "ok    crates.io sqlx-cli 0.8.6" || { echo "FAIL  crates.io"; fail=1; }

if [ $fail -eq 0 ]; then echo "monthly-probe: all pinned inputs available."; else echo "monthly-probe: SOME INPUTS UNAVAILABLE — vendor or re-pin before they rot further."; fi
exit $fail
