#!/bin/bash
# Bring the dedicated CI clone to the commit that triggered the workflow
# (GITHUB_SHA in Forgejo Actions; falls back to the branch head), including
# submodules. The clone lives outside any interactive checkout.
set -euo pipefail
. "$(dirname "$0")/env.sh"

token="$(grep -oP 'FORGEJO_TOKEN=\K.*' "$HOME/.config/forgejo/env")"
url="https://ivan:${token}@forgejo.ivanthegeek.com/ivan/talkyard.git"

cd "$TY_CI_REPO"
git fetch -q "$url" docker-only-build
git checkout -q "${GITHUB_SHA:-FETCH_HEAD}"
git submodule update --init --quiet
echo "ci clone at: $(git rev-parse --short HEAD) ($(git log -1 --format=%s | head -c 60))"
