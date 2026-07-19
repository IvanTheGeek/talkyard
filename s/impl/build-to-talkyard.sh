#!/bin/bash
# Builds to-talkyard. Runs INSIDE the nodejs container (see the Makefile
# 'to-talkyard' target): the container entrypoint cd's to the repo root and
# re-joins its arguments through `su -c "$*"`, so quoted `sh -c '...'`
# payloads get mangled — a single script path passes through unharmed.
set -e
# Non-interactive: pnpm may need to purge a node_modules created by another
# pnpm/layout (e.g. an old host install) — never prompt for that here.
export CI=true
cd "$(dirname "$0")/../../to-talkyard"
pnpm install --frozen-lockfile
pnpm run build
