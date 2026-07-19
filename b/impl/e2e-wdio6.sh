#!/bin/bash
# Inner wdio6 runner: enumerate tests/e2e/specs, optionally shard, run each
# spec via its own `s/wdio --only <name>` invocation — exactly how upstream's
# s/run-e2e-tests.sh drove this suite (one spec per wdio process; the conf
# derives browser count from the spec name, so no grouping flags needed).
# Runs inside ty-e2e-wdio6-runner (node 14; see b/e2e6).
#
# Options:
#   --shard N/M     run the Nth of M shards (default 1/1 = all)
#   --spec NAME     run only specs matching NAME (repeatable)
#   --dry-run       print the spec assignment and exit
set -uo pipefail

cd "$(dirname "$0")/../.."

shard="1/1"; dry_run=""; only_specs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --shard)   shard="$2"; shift 2 ;;
    --spec)    only_specs+=("$2"); shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "e2e-wdio6.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done
shard_n="${shard%%/*}"; shard_m="${shard##*/}"

# Deps: not vendored; install from the yarn lockfile (node 14 + bundled
# yarn 1.22; fibers 5.0.1 fetches a prebuilt for this exact node ABI).
if [ ! -x tests/e2e/node_modules/.bin/wdio ]; then
  echo "=== e2e6: installing tests/e2e deps (yarn, frozen lockfile) ==="
  ( cd tests/e2e && yarn install --frozen-lockfile ) || exit 1
fi

# Enumerate. Skip the spec template. Sorted => deterministic shards.
mapfile -t all < <(cd tests/e2e && ls specs/*.test.ts | grep -v '__e2e-test-template__' | sort)

if [ "$shard_m" -gt 1 ]; then
  kept=(); i=0
  for s in "${all[@]}"; do
    [ $(( i % shard_m + 1 )) -eq "$shard_n" ] && kept+=("$s")
    i=$(( i + 1 ))
  done
  all=("${kept[@]}")
fi

if [ ${#only_specs[@]} -gt 0 ]; then
  kept=()
  for s in "${all[@]}"; do
    for o in "${only_specs[@]}"; do
      case "$s" in *"$o"*) kept+=("$s"); break ;; esac
    done
  done
  all=("${kept[@]}")
fi

echo "=== e2e6 shard $shard: ${#all[@]} specs ==="
if [ -n "$dry_run" ]; then
  printf '%s\n' "${all[@]}"
  exit 0
fi

passed=0; failed=0; failures=()
for s in "${all[@]}"; do
  base="${s#specs/}"; base="${base%.test.ts}"
  echo
  echo "=== e2e6 spec: $base ($(( passed + failed + 1 ))/${#all[@]}) $(date -Is) ==="
  if s/wdio --only "$base"; then
    passed=$(( passed + 1 ))
  else
    failed=$(( failed + 1 ))
    failures+=("$base")
  fi
done

echo
echo "=== e2e6 shard $shard done: $passed passed, $failed failed ==="
if [ $failed -gt 0 ]; then
  printf 'FAILED: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
