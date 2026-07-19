# Shared helper for the --isolated mode: a private docker daemon in a
# docker:dind container, so builds/tests don't touch the host daemon at all.
# Fixes on busy machines: host ports 80/443 stay free (nested containers bind
# inside the dind network namespace), the prod build's no-unrelated-containers
# check always passes, and teardown is one container + one volume.
#
# The repo is bind-mounted into the dind container at its HOST path, so the
# compose bind mounts of nested containers (./:/opt/talkyard/app/ etc.)
# resolve to the real repo through dind's mount namespace — the same
# path-identity rule as b/build, one level deeper.
#
# Source this file, then call ensure_dind "$repo"; use $TY_DIND_DOCKER_HOST.

# Overridable, so independent contexts (e.g. the CI runner clone vs an
# interactive checkout — different repo paths!) get their OWN daemon, cache
# volume and network. One dind can only mount one repo path.
TY_DIND_NAME="${TY_DIND_NAME:-ty-dind}"
TY_DIND_NET="${TY_DIND_NET:-ty-build-net}"
TY_DIND_VOL="${TY_DIND_VOL:-ty-dind-cache}"

# TY_DIND_OFFLINE=1: hermetic mode — the dind daemon goes on an *internal*
# bridge (no NAT, no egress), but reuses the same image-cache volume a
# previous online run populated. Any step that tries to fetch anything
# fails fast, proving the vendored inputs are complete. Separate container
# and network names, so online and offline daemons can't be confused.
_ty_dind_base_name="$TY_DIND_NAME"
if [ -n "${TY_DIND_OFFLINE:-}" ]; then
  TY_DIND_NAME="${_ty_dind_base_name}-offline"
  TY_DIND_NET="${TY_DIND_NET}-offline"
fi
# Digest-pinned (b/pin-digests); same engine major as typical hosts.
TY_DIND_IMAGE=docker:29-dind@sha256:bfec1f5159c63a81ca6fdedbd81404d2c0e16378ed0feec3bb3fbf3998847659
TY_DIND_DOCKER_HOST=tcp://$TY_DIND_NAME:2375

ensure_dind() {
  local repo="$1"
  local net_opts=()
  [ -n "${TY_DIND_OFFLINE:-}" ] && net_opts=(--internal)
  docker network inspect "$TY_DIND_NET" >/dev/null 2>&1 \
    || docker network create "${net_opts[@]}" "$TY_DIND_NET" >/dev/null

  # The cache volume can back only ONE running dockerd — stop the other-mode
  # daemon (online vs offline) before starting this one.
  local other="$_ty_dind_base_name"
  [ -z "${TY_DIND_OFFLINE:-}" ] && other="${_ty_dind_base_name}-offline"
  if docker ps -a --format '{{.Names}}' | grep -qx "$other"; then
    echo "dind: removing $other first (the cache volume can back only one daemon)" >&2
    docker rm -f "$other" >/dev/null
  fi

  if ! docker ps --format '{{.Names}}' | grep -qx "$TY_DIND_NAME"; then
    docker rm -f "$TY_DIND_NAME" >/dev/null 2>&1 || true
    echo "dind: starting $TY_DIND_NAME (image cache in volume $TY_DIND_VOL) ..." >&2
    docker run -d --name "$TY_DIND_NAME" --privileged \
      --network "$TY_DIND_NET" \
      -e DOCKER_TLS_CERTDIR= \
      -v "$TY_DIND_VOL":/var/lib/docker \
      -v "$repo":"$repo" \
      "$TY_DIND_IMAGE" >/dev/null
  fi

  # Wait until the inner daemon answers.
  local i
  for i in $(seq 1 30); do
    if docker exec "$TY_DIND_NAME" docker version >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "dind: daemon in $TY_DIND_NAME didn't come up" >&2
  return 1
}

# The container name resolves only on the bridge net; from the HOST, use the
# container's bridge IP (routable on Linux).
dind_host_docker_host() {
  local ip
  ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$TY_DIND_NET\").IPAddress}}" "$TY_DIND_NAME")"
  echo "tcp://$ip:2375"
}

clean_dind() {
  docker rm -f "$TY_DIND_NAME" >/dev/null 2>&1 || true
  docker volume rm "$TY_DIND_VOL" >/dev/null 2>&1 || true
  docker network rm "$TY_DIND_NET" >/dev/null 2>&1 || true
  echo "dind: removed container, cache volume, network." >&2
}
