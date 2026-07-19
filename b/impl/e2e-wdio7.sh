#!/bin/bash
# Inner wdio7 runner: enumerate specs, bucket by browser count, optionally
# take one shard, run each bucket with its --Nbr flag via s/wdio-7.
# Runs inside ty-e2e-runner (see b/e2e), but works in any node-24 + chrome
# environment. Talkyard sets browsers-per-spec via CLI flags (--2br/--3br/
# --4br; untagged = 1 browser), so specs MUST run grouped by that tag.
#
# Options:
#   --shard N/M            run the Nth of M balanced shards (default 1/1 = all)
#   --retries K            wdio --specFileRetries (default 2)
#   --spec NAME            run only this spec (repeatable; overrides sharding)
#   --skip-expected-fails  drop specs matching b/impl/e2e-expected-env-fails.txt
#                          (environmental failures: IdP secrets, static-site
#                          servers, real egress — the curated CI green gate)
#   --dry-run              print the spec assignment and exit
set -uo pipefail

cd "$(dirname "$0")/../.."

shard="1/1"; retries=2; dry_run=""; skip_expected=""; only_specs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --shard)   shard="$2"; shift 2 ;;
    --retries) retries="$2"; shift 2 ;;
    --spec)    only_specs+=("$2"); shift 2 ;;
    --skip-expected-fails) skip_expected=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "e2e-wdio7.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done
shard_n="${shard%%/*}"; shard_m="${shard##*/}"
if ! [ "$shard_n" -ge 1 ] 2>/dev/null || ! [ "$shard_n" -le "$shard_m" ] 2>/dev/null; then
  echo "e2e-wdio7.sh: bad --shard '$shard', want N/M with 1<=N<=M" >&2; exit 2
fi

# Deps: the e2e node_modules aren't vendored; install from the lockfile.
if [ ! -x tests/e2e-wdio7/node_modules/.bin/wdio ]; then
  echo "=== e2e: installing tests/e2e-wdio7 deps (pnpm, frozen lockfile) ==="
  ( cd tests/e2e-wdio7 && pnpm install --frozen-lockfile ) || exit 1
fi

# Enumerate + bucket. Sorted => deterministic shard assignment.
mapfile -t all < <(cd tests/e2e-wdio7 && ls specs/*.e2e.ts | sort)

# Expected-env-fail filtering happens BEFORE sharding, so shard sizes stay
# balanced over the specs that actually run.
if [ -n "$skip_expected" ]; then
  mapfile -t patterns < <(grep -v '^\s*#' b/impl/e2e-expected-env-fails.txt | grep -v '^\s*$')
  kept=(); skipped=0
  for s in "${all[@]}"; do
    base="${s#specs/}"
    hit=""
    for p in "${patterns[@]}"; do
      # shellcheck disable=SC2254
      case "$base" in $p) hit=1; break ;; esac
    done
    if [ -n "$hit" ]; then skipped=$(( skipped + 1 )); else kept+=("$s"); fi
  done
  echo "=== e2e: skipping $skipped expected-env-fail specs (b/impl/e2e-expected-env-fails.txt)"
  all=("${kept[@]}")
fi
g1=(); g2=(); g3=(); g4=()
for s in "${all[@]}"; do
  case "$s" in
    *.4br.*) g4+=("$s") ;;
    *.3br.*) g3+=("$s") ;;
    *.2br.*) g2+=("$s") ;;
    *)       g1+=("$s") ;;
  esac
done

# Round-robin within each bucket: spec i goes to shard (i mod M) + 1.
take_shard() {  # args: names of specs; prints the ones for our shard
  local i=0 s
  for s in "$@"; do
    if [ $(( i % shard_m + 1 )) -eq "$shard_n" ]; then echo "$s"; fi
    i=$(( i + 1 ))
  done
}
if [ "$shard_m" -gt 1 ]; then
  mapfile -t g1 < <(take_shard "${g1[@]}")
  mapfile -t g2 < <(take_shard "${g2[@]}")
  mapfile -t g3 < <(take_shard "${g3[@]}")
  mapfile -t g4 < <(take_shard "${g4[@]}")
fi

# --spec smoke mode: filter every bucket down to the named specs.
if [ ${#only_specs[@]} -gt 0 ]; then
  filter() { local s o; for s in "$@"; do for o in "${only_specs[@]}"; do
               case "$s" in *"$o"*) echo "$s" ;; esac; done; done; }
  mapfile -t g1 < <(filter "${g1[@]}")
  mapfile -t g2 < <(filter "${g2[@]}")
  mapfile -t g3 < <(filter "${g3[@]}")
  mapfile -t g4 < <(filter "${g4[@]}")
fi

total=$(( ${#g1[@]} + ${#g2[@]} + ${#g3[@]} + ${#g4[@]} ))
echo "=== e2e shard $shard: $total specs | 1br:${#g1[@]} 2br:${#g2[@]} 3br:${#g3[@]} 4br:${#g4[@]} ==="
if [ -n "$dry_run" ]; then
  for s in "${g1[@]}" "${g2[@]}" "${g3[@]}" "${g4[@]}"; do echo "$s"; done
  exit 0
fi

free_chromedriver() {
  pkill -9 chromedriver 2>/dev/null
  sleep 2
  return 0
}

overall=0
run_group() {
  local flag="$1"; shift
  local name="$1"; shift
  [ $# -eq 0 ] && return 0
  echo "=== e2e group $name ($# specs) start $(date -Is) ==="
  free_chromedriver
  local specargs=() s
  for s in "$@"; do specargs+=(--spec "$s"); done
  # shellcheck disable=SC2086
  s/wdio-7 --cd --headless $flag --bail 0 --specFileRetries "$retries" "${specargs[@]}"
  local rc=$?
  [ $rc -ne 0 ] && overall=$rc
  echo "=== e2e group $name done exit=$rc $(date -Is) ==="
}

run_group ""      1br "${g1[@]}"
run_group "--2br" 2br "${g2[@]}"
run_group "--3br" 3br "${g3[@]}"
run_group "--4br" 4br "${g4[@]}"
free_chromedriver

echo "=== e2e shard $shard done, exit $overall ==="
exit $overall
