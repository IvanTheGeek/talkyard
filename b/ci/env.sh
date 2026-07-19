# Shared CI environment for the self-hosted Forgejo runner (host mode, this
# box). Sourced by the b/ci/*.sh entry points. All CI work happens in a
# DEDICATED clone with its OWN isolated docker daemon, so interactive use of
# other checkouts on the same box never collides with CI.

export TY_CI_HOME="${TY_CI_HOME:-$HOME/forgejo-runner}"
export TY_CI_REPO="$TY_CI_HOME/talkyard"
export TY_CI_STATE="$TY_CI_HOME/state"
mkdir -p "$TY_CI_STATE" "$TY_CI_STATE/logs"

# CI's own dind context (see b/impl/dind-lib.sh) — separate daemon, cache
# volume and network from any interactive --isolated use.
export TY_DIND_NAME=ty-dind-ci
export TY_DIND_NET=ty-build-net-ci
export TY_DIND_VOL=ty-dind-ci-cache

export TY_NONINTERACTIVE=1

ci_log_dir() {
  local d="$TY_CI_STATE/logs/$(date +%Y-%m-%d)"
  mkdir -p "$d"
  echo "$d"
}
