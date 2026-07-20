#!/bin/bash
# Nightly arm64: cross-arch prod-image build + emulated boot smoke, entirely
# inside the CI dind daemon (host ports and the host image store untouched).
# The runtime images build for linux/arm64 via qemu/binfmt; sbt + gulp run
# native (their outputs are arch-independent). See b/README.md "Dual-arch".
#
# Change guard like nightly-e2e: skips when HEAD == the marker from the last
# green run, unless TY_FORCE=1 (set on manual dispatch).
#
# TY_PUBLISH_ARM64=<registry-prefix> additionally pushes the images as
# <prefix>/talkyard-<svc>:<version>-<sha>-arm64 (uses the box-local docker
# login; client-side creds work over DOCKER_HOST to the dind daemon).
set -euo pipefail
. "$(dirname "$0")/env.sh"
cd "$TY_CI_REPO"

# Own dind context — NOT ty-dind-ci: the arm64 pass overwrites the shared
# :latest tags (web etc.) that nightly-e2e's dev stack boots from; sharing
# the daemon would leave e2e fronted by an emulated arm64 nginx forever.
export TY_DIND_NAME=ty-dind-ci-arm64
export TY_DIND_NET=ty-build-net-ci-arm64
export TY_DIND_VOL=ty-dind-ci-arm64-cache

head="$(git rev-parse HEAD)"
marker="$TY_CI_STATE/last-arm64-green"
if [ -z "${TY_FORCE:-}" ] && [ -f "$marker" ] && [ "$(cat "$marker")" = "$head" ]; then
  echo "nightly-arm64: HEAD unchanged since last green run ($head) — skipping."
  exit 0
fi

logs="$(ci_log_dir)"
echo "nightly-arm64: logs -> $logs"

if [ "$(docker run --rm --platform linux/arm64 alpine:3.22.3 uname -m 2>/dev/null || true)" != "aarch64" ]; then
  echo "nightly-arm64: no arm64 emulation — install qemu-user-static on this box."
  exit 1
fi

# Prod-test stack file set MINUS debug.yml (it publishes app/cache/rdb/search
# ports we don't need — the smoke polls via docker exec only), plus: no
# published web ports either.
smoke="sudo env VERSION_TAG=latest DOCKER_REG_ORG=debiki POSTGRES_PASSWORD=public \
docker compose -p tya-smoke \
-f modules/ed-prod-one-test/docker-compose.yml \
-f modules/ed-prod-one-test-override.yml \
-f docker-compose-no-limits.yml \
-f b/ci/arm64-smoke-noports.yml"

cleanup() {
  b/build --isolated bash -c "$smoke down -v" >/dev/null 2>&1 || true
}
trap cleanup EXIT
# Also clean at START: a hard-killed (SIGKILL/reboot) previous run can leave
# the tya-smoke stack running in the dind, which would trip the build's
# no-unrelated-containers guard.
cleanup

echo "=== arm64 prod images (runtime images emulated; sbt/gulp native) ==="
b/build --isolated --arch arm64 make prod-images-skip-tests > "$logs/arm64-build.log" 2>&1 \
  || { echo "arm64 build FAILED:"; tail -30 "$logs/arm64-build.log"; exit 1; }

echo "=== emulated boot smoke ==="
[ -f modules/ed-prod-one-test/secrets/postgres_password.txt ] \
  || echo public > modules/ed-prod-one-test/secrets/postgres_password.txt
b/build --isolated bash -c "$smoke up -d web app rendr cache rdb search egressp" \
  > "$logs/arm64-smoke.log" 2>&1

ready=""
for i in $(seq 1 240); do
  st="$(docker exec "$TY_DIND_NAME" docker inspect \
        --format '{{.State.Health.Status}}' tya-smoke-app-1 2>/dev/null || true)"
  if [ "$st" = "healthy" ]; then ready=1; echo "app healthy (~$(( i * 5 ))s)"; break; fi
  [ $(( i % 24 )) -eq 0 ] && echo "  still starting (~$(( i * 5 / 60 )) min; emulated JVM is slow)"
  sleep 5
done
if [ -z "$ready" ]; then
  echo "app never became healthy; log tail:"
  docker exec "$TY_DIND_NAME" docker logs --tail 40 tya-smoke-app-1 2>&1 | tail -40
  exit 1
fi

arch="$(docker exec "$TY_DIND_NAME" docker exec tya-smoke-app-1 uname -m)"
if [ "$arch" != "aarch64" ]; then
  echo "app container arch is '$arch', expected aarch64 — not an arm64 image?"
  exit 1
fi
# The healthcheck endpoint answers even with no DB (found live: a boot-time
# DNS hiccup left the app healthy-but-stateless) — assert migrations ran.
# With a grace window: sqlx's "Done migrating" line can flush to the log
# stream SECONDS AFTER the app already turned healthy (lost race = the
# first CI run's false failure, 2026-07-19).
migrated=''
for i in $(seq 1 12); do
  applog="$(docker exec "$TY_DIND_NAME" docker logs tya-smoke-app-1 2>&1 || true)"
  if echo "$applog" | grep -q 'Done migrating database'; then migrated=1; break; fi
  if echo "$applog" | grep -q 'Error migrating database'; then break; fi
  sleep 5
done
if [ -z "$migrated" ]; then
  echo "app is healthy but the DB migration never succeeded; log tail:"
  docker exec "$TY_DIND_NAME" docker logs --tail 30 tya-smoke-app-1 2>&1 | tail -30
  exit 1
fi
echo "smoke OK: app healthy, aarch64, DB migrated"

if [ -n "${TY_PUBLISH_ARM64:-}" ]; then
  version_tag="$(cat version.txt)-$(git rev-parse --short HEAD)"
  . b/impl/dind-lib.sh
  echo "=== publish -> ${TY_PUBLISH_ARM64}/talkyard-*:${version_tag}-arm64 ==="
  DOCKER_HOST="$(dind_host_docker_host)" \
    b/publish-runtime-images "$TY_PUBLISH_ARM64" "${version_tag}-arm64" \
    > "$logs/arm64-publish.log" 2>&1 \
    || { echo "publish FAILED:"; tail -20 "$logs/arm64-publish.log"; exit 1; }
fi

echo "$head" > "$marker"
echo "nightly-arm64: GREEN — marker updated."
