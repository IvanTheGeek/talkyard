# ty-builder: run Talkyard's build orchestration (make + s/* scripts) inside a
# container, so the host needs only Docker + git. The heavy work (sbt, gulp)
# already runs in the app/nodejs compose containers; this image supplies the
# thin host layer the scripts expect: node 24, pnpm, GNU make, git, bash,
# docker CLI + compose plugin, and a no-op `sudo` shim.
#
# IMPORTANT: this image talks to the HOST docker daemon via the mounted
# /var/run/docker.sock, so the repo must be bind-mounted at the SAME absolute
# path as on the host — see b/build, which enforces that.
#
# Same node base as images/nodejs/Dockerfile, so tool versions stay aligned.

FROM node:24.14.0-trixie-slim@sha256:8c8f12cedb96c3b59642cf30d713943c2b223990c9919b96a141681f62e6e292

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash git make curl ca-certificates unzip gzip jq procps util-linux gnupg \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# pnpm: the repo's lockfiles are lockfileVersion 9.0. Pinned by major here;
# exact-version + integrity pinning is planned in the hermetic-build pass.
RUN npm install -g pnpm@10.34.5

# No-op sudo shim: the build scripts run `sudo docker compose ...` and
# `sudo VAR=val docker compose ...`. Inside this container the invoking user
# already has docker-socket access (see entrypoint), so sudo just needs to
# pass env assignments through and exec.
COPY sudo-shim.sh /usr/local/bin/sudo
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/sudo /entrypoint.sh \
 && git config --system --add safe.directory '*' \
 && git config --system protocol.file.allow always

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
