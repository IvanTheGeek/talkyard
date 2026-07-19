# ty-e2e-wdio6-runner: run the LEGACY Webdriverio 6 suite (tests/e2e/,
# ~137 specs) with no host dependencies beyond Docker. These tests need
# Node 14 EXACTLY (wdio 6 sync mode / fibers) — which is precisely why they
# became painful to run on hosts (node-gyp vs host node); a frozen node-14
# container ends that.
#
# The browser comes from the separate `tye2ebrowser` Selenium container
# (selenium/standalone-chrome, Chrome ~86 — version-matched to this suite's
# chromedriver 86 pins). The runner connects to it via the
# TY_E2E_REMOTE_SELENIUM env hook in tests/e2e/wdio.conf.ts, so no Java and
# no browser needed in THIS image. Run with --network=host (see b/e2e6).
#
# node:14 is EOL and Debian 11 goes apt-archive-only in Aug 2026: this image
# is a frozen artifact — digest-pinned, expect never to change its base.

FROM node:14.21.3-bullseye-slim@sha256:0f5b374fae506741ff14db84daff2937ae788e88fb48a6c66d15de5ee808ccd3

# yarn 1.22 ships in the base image (node-14-era images bundle it).
# python3/make/g++: node-gyp fallback if the fibers 5.0.1 prebuilt download
# ever fails.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash git curl ca-certificates procps util-linux dnsmasq \
      python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && git config --system --add safe.directory '*' || true

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
