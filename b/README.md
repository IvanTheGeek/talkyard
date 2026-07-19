# b/ — Docker-only build harness

Build, test, and package Talkyard with **only Docker (+ git) on the host** —
no Nix, Node, pnpm, sbt, JDK, or Chrome. Everything heavy already ran in
containers upstream (sbt in the `app` dev container, gulp in `nodejs`);
these scripts containerize the thin orchestration layer that used to need a
`nix develop` shell, and add CI conveniences.

Requires: Linux amd64, Docker with the compose + buildx plugins, and (for
Elasticsearch) `sysctl -w vm.max_map_count=262144` — or run ES with
`node.store.allow_mmap: false` on locked-down runners.

## Entry points

| Command | What |
|---|---|
| `b/build <cmd…>` | Run any command (usually `make …` or `b/check`) inside the ty-builder container against the host docker daemon. Repo is mounted at its **host-identical absolute path** — required, because compose bind mounts resolve on the daemon side. |
| `b/build --isolated <cmd…>` | Same, but against a **private docker:dind daemon**: host ports stay free, the prod build's no-other-containers check always passes, teardown = `b/build --clean-isolated`. First run is cold; the image cache persists in a volume. |
| `TY_DIND_OFFLINE=1 b/build --isolated <cmd…>` | Hermetic mode: the private daemon gets an `--internal` network (zero egress) but reuses the cache a prior online run filled. Proves the vendored inputs are complete. |
| `b/check` | Fast PR tier: submodules → node_modules → dev images → all client TS/CSS bundles → sbt compile + full unit/app test suite. ~4 min warm, ~8 min on a cold daemon. Green on main (996/996). Emits a per-stage timing table (also `target/ty-build-summary.txt`). |
| `b/e2e [--shard N/M] [--skip-expected-fails] [--spec X]` | wdio7 e2e in the ty-e2e-runner container (node 24 + Debian chromium/chromedriver — a version-matched pair). The Talkyard stack must already be up. `--shard N/M` = balanced CI matrix shards; `--skip-expected-fails` = the curated green gate (see below). `--isolated` targets the dind daemon's stack. |
| `make prod-images-skip-tests` (via `b/build`) | Full release build + unit tests, no e2e. Runs unattended (`TY_NONINTERACTIVE`). |
| `b/push-build-images` / `b/pull-build-images <registry>` | Publish/fetch the four expensive images (builder, e2e-runner, nodejs, app-dev) so cold machines skip ~15 min of building. `TY_BUILDER_IMG`/`TY_E2E_RUNNER_IMG` run straight from a prebuilt image. |
| `b/pin-digests [--check]` | Digest-pin every base image (`FROM tag@sha256:…`). `--check` is the CI guard against unpinned FROMs. |
| `b/cache-key` | Stable content-hash keys (submodules / node deps / images / sbt) for CI cache steps. |

Env knobs: `TY_BUILD_HEAP_MB` (sbt heap; default ≥5120, prod uses 8192),
`TY_NONINTERACTIVE` (default 1 inside b/build), `TY_IMG_REGISTRY`.

## Routing decisions — old machinery this harness deliberately bypasses

Decided 2026-07-19; revisit only if upstream changes.

1. **E2E runner path:** the canonical runner here is `b/e2e`
   (grouped-by-browser-count, shardable, containerized). We do NOT use
   `s/run-e2e-tests.sh` (self-declared deprecated, host-node, mixes the
   wdio6 suite in) nor `s/tyd e2e` (needs deno + a nix shell). Upstream's
   `make prod-images` still calls `s/run-e2e-tests.sh --prod` internally —
   our CI therefore uses `make prod-images-skip-tests` for the build and a
   separate `b/e2e` stage against the prod-test stack for e2e.
2. **Security tests:** defunct at this commit — the compose `test` service
   is commented out, its build context `images/gulp/` and the `tests/security/`
   sources are gone. Excluded from the harness; flagged as an upstream
   question (resurrect or delete `s/d-run-security-tests`).
3. **`docker-compose.it.yml`:** references env vars that exist nowhere and
   is invoked by nothing (Matrix/n8n integration fixtures). Ignored.
4. **Gatsby embedded-comments fixtures:** the fixture build is hard-broken
   upstream (`echo "How [pnpm_0_yarn]?"; exit 1` in s/run-e2e-tests.sh), so
   Gatsby embcom specs cannot even build their prerequisites. They are in
   the expected-env-fails list (below).
5. **wdio6 (tests/e2e/, node 14):** NOT dead — still vital; runs via
   `b/e2e6` + the `ty-e2e-wdio6-runner` container (frozen node 14 — ends the
   node-gyp/fibers host pain) against the pinned `tye2ebrowser` Selenium
   container (Chrome ~86, matching this suite's chromedriver 86 pins), via
   the `TY_E2E_REMOTE_SELENIUM` hook in tests/e2e/wdio.conf.ts. One wdio
   process per spec, exactly like upstream's old runner drove it.

## The curated e2e green gate

`b/impl/e2e-expected-env-fails.txt` lists spec patterns that fail for
*environmental* reasons on a plain runner (external-IdP secrets, static-site
fixture servers on :8080/:8000, real internet egress for link previews, the
fakeweb container for webhooks, one known-flaky spec). `b/e2e
--skip-expected-fails` drops them before sharding — that subset is the CI
gate; the nightly full run keeps measuring the whole suite. Two categories
are recoverable later: webhooks (start `fakeweb` via
`docker compose --profile e2etests up -d fakeweb`) and non-Gatsby embcom
(add an http-server sidecar to the runner image).

## Dual-arch (amd64 + arm64)

The chain can produce the runtime images for linux/arm64 (Raspberry Pi,
Apple Silicon, arm64 cloud) as well as native amd64:

- `b/build [--isolated] --arch arm64 make prod-images-skip-tests` — exports
  `TY_TARGET_ARCH=arm64`; s/impl/build-prod-images.sh scopes it (as
  `DOCKER_DEFAULT_PLATFORM`) to the RUNTIME image builds only — gulp, sbt
  and the dev images stay native; their outputs are arch-independent. The
  arch-specific layers (OpenResty compile, sqlx-cli cargo build, ES plugin
  install, apt/apk) build under qemu/binfmt — install `qemu-user-static`
  once on the build box; layer caching makes rebuilds cheap.
- `TY_REUSE_APP_DIST=1` skips sbt test+dist when `target/universal/*.zip`
  already exists — for a second-arch pass right after a native build.
- Publishing: the build tags images `:latest` in the building daemon (same
  as amd64). `b/publish-runtime-images <prefix> <tag>` pushes all eight
  runtime images from the CURRENT daemon (set `DOCKER_HOST` at the dind
  daemon for --isolated builds) — use per-arch tags
  `<version>-<sha>-amd64|-arm64`, then `b/stitch-manifests <prefix>
  <version>-<sha>` merges them registry-side into one multi-arch tag, so
  any machine pulls its own arch automatically.
- CI: `.forgejo/workflows/nightly-arm64.yml` (00:30, change-guarded) builds
  arm64 inside the CI dind, boot-smokes the stack emulated (app healthcheck
  + `uname -m` == aarch64) and pushes `-arm64` tags. The monthly probe
  asserts qemu binfmt keeps working on the runner.
- The one arch-pinned base was images/search's ES tag (`9.3.1-amd64`), now
  the multi-arch `9.3.1` index digest. b/pin-digests pins manifest-LIST
  digests, so pins stay arch-neutral across the board.
