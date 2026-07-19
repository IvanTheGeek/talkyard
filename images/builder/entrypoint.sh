#!/bin/bash
# ty-builder entrypoint: run as a user matching the bind-mounted repo's owner
# (so generated files aren't root-owned — same idea as images/nodejs), with
# docker-socket access via a supplementary group. Refuses to run the build as
# uid 0 because s/build-prod-images.sh refuses root anyway.
set -e

uid="${HOST_UID:-1000}"
gid="${HOST_GID:-1000}"
docker_gid="${DOCKER_GID:-}"

if ! getent group "$gid" >/dev/null; then
  groupadd -g "$gid" owner
fi
if ! getent passwd "$uid" >/dev/null; then
  useradd -m -u "$uid" -g "$gid" -s /bin/bash owner
fi
user="$(getent passwd "$uid" | cut -d: -f1)"

if [ -n "$docker_gid" ]; then
  if ! getent group "$docker_gid" >/dev/null; then
    groupadd -g "$docker_gid" dockerhost
  fi
  usermod -aG "$(getent group "$docker_gid" | cut -d: -f1)" "$user"
fi

# setpriv keeps the environment — point HOME at the mapped user's home, else
# tools (docker CLI plugin discovery, pnpm, git) trip over unreadable /root.
HOME="$(getent passwd "$uid" | cut -d: -f6)"
export HOME

exec setpriv --reuid="$uid" --regid="$gid" --init-groups "$@"
