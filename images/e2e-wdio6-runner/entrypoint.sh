#!/bin/bash
# ty-e2e-runner entrypoint: (1) make sure wildcard *.localhost hostnames
# resolve to 127.0.0.1 — the e2e specs create sites at e2e-test-*.localhost
# (see docs/wildcard-dot-localhost.md). On hosts with systemd-resolved this
# already works through the host's resolver stub (we run with --network=host);
# otherwise fall back to a local dnsmasq. (2) drop to a user matching the
# bind-mounted repo owner, like images/nodejs does.
set -e

if ! getent hosts e2e-test-probe-x7.localhost >/dev/null 2>&1; then
  echo 'address=/localhost/127.0.0.1' > /etc/dnsmasq.d/ty-wildcard-localhost.conf
  dnsmasq   # daemonizes itself
  echo 'nameserver 127.0.0.1' > /etc/resolv.conf
  if ! getent hosts e2e-test-probe-x7.localhost >/dev/null 2>&1; then
    echo "entrypoint: WARNING: *.localhost still doesn't resolve — e2e API" >&2
    echo "requests to e2e-test-*.localhost hostnames will fail." >&2
  fi
fi

uid="${HOST_UID:-1000}"
gid="${HOST_GID:-1000}"

if ! getent group "$gid" >/dev/null; then
  groupadd -g "$gid" owner
fi
if ! getent passwd "$uid" >/dev/null; then
  useradd -m -u "$uid" -g "$gid" -s /bin/bash owner
fi

HOME="$(getent passwd "$uid" | cut -d: -f6)"
export HOME

exec setpriv --reuid="$uid" --regid="$gid" --init-groups "$@"
