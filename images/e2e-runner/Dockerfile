# ty-e2e-runner: run the Webdriverio 7 e2e suite (tests/e2e-wdio7) with no
# host dependencies beyond Docker. Node 24 (what s/wdio-7 requires), pnpm,
# and Debian's chromium + chromium-driver — an always-version-matched
# browser/driver pair, so no chromedriver download or version juggling.
#
# Run with --network=host (see b/e2e): the specs reach the Talkyard web
# container on 127.0.0.1:80/443, fakeweb on :8090, and static file servers.
# The wdio config picks up the container specifics via TY_E2E_* env vars
# ([ty_e2e_env] in tests/e2e-wdio7/wdio.conf.ts) — set by b/e2e.

FROM node:24.14.0-trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash git curl ca-certificates procps util-linux \
      chromium chromium-driver dnsmasq \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm@10

# The chromedriver npm package's postinstall downloads a driver binary we
# never use (we point wdio at /usr/bin/chromedriver) — skip the download.
ENV CHROMEDRIVER_SKIP_DOWNLOAD=true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && git config --system --add safe.directory '*'

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
