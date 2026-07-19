#!/bin/bash
# Publish the warm build/runner images to the self-hosted registry (and
# optionally ghcr as mirror). Manual-dispatch only. Uses the box-local
# docker logins (Forgejo package token + gh auth) — no secrets in CI config.
set -euo pipefail
. "$(dirname "$0")/env.sh"
cd "$TY_CI_REPO"

b/push-build-images forgejo.ivanthegeek.com/ivan
if [ -n "${TY_PUBLISH_GHCR_MIRROR:-}" ]; then
  b/push-build-images ghcr.io/ivanthegeek
fi
