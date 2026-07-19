# Stage timing + result summary for the b/ scripts. Source this, call
# ty_stages_init once, then ty_stage "name" before each phase. On ANY exit
# (success or failure) an EXIT trap closes the last stage and prints a
# per-stage table; the same table is written to target/ty-build-summary.txt
# for CI artifact upload.
#
#   . b/impl/stages-lib.sh
#   ty_stages_init
#   ty_stage "compile"
#   ...
# A stage is 'ok' when the next stage starts (we only got there because the
# previous one succeeded) and 'FAIL' when the script exits nonzero mid-stage.

ty_stages_init() {
  _ty_t0=$(date +%s)
  _ty_stage=""
  _ty_summary="${TY_SUMMARY_FILE:-target/ty-build-summary.txt}"
  mkdir -p "$(dirname "$_ty_summary")"
  : > "$_ty_summary"
  trap '_ty_stages_on_exit $?' EXIT
}

ty_stage() {
  _ty_stage_close ok
  _ty_stage="$*"
  _ty_st0=$(date +%s)
  echo
  echo "=== [$(( $(date +%s) - _ty_t0 ))s] $* ==="
}

_ty_stage_close() {
  if [ -n "$_ty_stage" ]; then
    printf '%-4s %6ss  %s\n' "$1" "$(( $(date +%s) - _ty_st0 ))" "$_ty_stage" \
      >> "$_ty_summary"
  fi
  _ty_stage=""
}

_ty_stages_on_exit() {
  local rc=$1
  if [ "$rc" -eq 0 ]; then _ty_stage_close ok; else _ty_stage_close FAIL; fi
  echo
  echo "=== stage summary — exit $rc, total $(( $(date +%s) - _ty_t0 ))s ==="
  cat "$_ty_summary" 2>/dev/null
  echo "(also in $_ty_summary)"
}
