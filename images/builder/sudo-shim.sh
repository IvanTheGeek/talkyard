#!/bin/sh
# No-op sudo replacement for use inside the ty-builder container.
# Supports the invocation shapes Talkyard's build scripts use:
#   sudo cmd args...
#   sudo VAR=val [VAR2=val2 ...] cmd args...
#   sudo -E cmd ... / sudo -u user cmd ...   (flags accepted and ignored)
while [ $# -gt 0 ]; do
  case "$1" in
    -E|-n|-H) shift ;;
    -u) shift 2 ;;
    --) shift; break ;;
    *=*) export "$1"; shift ;;
    *) break ;;
  esac
done
exec "$@"
