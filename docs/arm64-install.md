# Installing Talkyard on ARM64/AArch64 (Raspberry Pi, Apple Silicon, ARM cloud)

*(ARM64 and AArch64 are two names for the same 64-bit ARM architecture —
this page uses both so either search term finds it. Docker calls the
platform `arm64`; `uname -m` prints `aarch64`.)*

**Status: experimental — and unofficial.** These are community-built ARM64
images of Talkyard v1, produced by the `b/` Docker-only build pipeline in
this fork (see [`b/README.md`](../b/README.md), section "Dual-arch"). That
pipeline is the fork maintainer's own tooling — **not sanctioned by, or
affiliated with, the upstream Talkyard project**. The Talkyard application
code itself is **unchanged upstream source** (v1.2026.004); this fork adds
only build/packaging tooling around it. The full stack has been verified
end-to-end under qemu emulation (boots, migrates, serves HTTPS); validation
on real ARM hardware is in progress. Use for experiments and non-critical
forums; keep backups.

Background: the port turned out to be packaging, not code — an audit and the
change history are written up here:
<https://forum.ivanthegeek.com/-208/how-hard-would-it-be-to-build-and-run-talkyard-on-arm64-eg-a-raspberry-pi>

## What you need

- A 64-bit ARMv8 machine: Raspberry Pi 4/5 (a **64-bit OS is mandatory** —
  Raspberry Pi OS 64-bit or Debian arm64), an Apple Silicon Mac running
  Docker Desktop/OrbStack/Colima, or any arm64 cloud VM.
- **8 GB RAM recommended** (the stack measures ~3.4 GB with production heaps;
  4 GB works with the smaller memory overlay, see below).
- **SSD/NVMe strongly recommended** on a Pi — Postgres + ElasticSearch are
  hard on SD cards, in both speed and lifespan.
- Docker Engine + the compose plugin, git.

## The images

Eight ARM64/AArch64 runtime images per release, published to a Forgejo container registry
that allows **anonymous pulls** (docker negotiates the token flow
automatically — no account needed):

```
forgejo.ivanthegeek.com/ivan/talkyard-{app,web,rendr,cache,rdb,search,egressp,backup}:<version>-<gitsha>-arm64
```

Browse available tags: <https://forgejo.ivanthegeek.com/ivan/-/packages>
(pick the newest `-arm64` tag; all eight components share the same tag).

Each image's architecture is asserted at build and publish time; the git sha
in the tag is the exact fork commit it was built from, so you can audit the
sources. If you'd rather build your own: clone this fork and run
`./b/build --isolated --arch arm64 make prod-images-skip-tests`
(needs Docker + git + `qemu-user-static` on an amd64 box, or native ARM).

## Install

This mirrors the standard [talkyard-prod-one](https://github.com/debiki/talkyard-prod-one)
install — only the deltas are spelled out here; for general steps (firewall,
mail server config, etc.) follow upstream's README alongside.

1. **Host prep** (Pi/VM; Docker Desktop on macOS ships these defaults):

   ```bash
   # ElasticSearch bootstrap requirement:
   echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-talkyard.conf
   sudo sysctl --system
   ```

2. **Get the deployment skeleton:**

   ```bash
   sudo git clone https://github.com/debiki/talkyard-prod-one /opt/talkyard
   cd /opt/talkyard
   ```

3. **Point it at the ARM64 images** — edit `.env`:

   ```ini
   DOCKER_REG_ORG=forgejo.ivanthegeek.com/ivan
   PINNED_VERSION_TAG=v1.2026.004-<gitsha>-arm64   # newest tag from the packages page
   ```

   Use `PINNED_VERSION_TAG` (not `VERSION_TAG`): the compose file resolves
   `${PINNED_VERSION_TAG:-${VERSION_TAG}}`, and the pin survives the upgrade
   scripts. **Do not run `scripts/upgrade-if-needed.sh`** — it follows
   upstream's amd64 release channel; upgrades here are a manual re-pin to a
   newer `-arm64` tag (then `docker compose pull && docker compose up -d`).

4. **Memory profile** — pick the overlay matching your RAM:

   ```bash
   cp mem/4g.yml docker-compose.override.yml    # 4 GB machine
   # or mem/8G.yml on an 8 GB Pi 5
   ```

5. **Configure** `conf/app/play-framework.conf` as in a normal install:
   `talkyard.hostname`, `talkyard.becomeOwnerEmailAddress`, a fresh
   `play.http.secret.key` (`openssl rand -hex 40`), and your SMTP settings.
   Create `secrets/postgres_password.txt` (e.g. `openssl rand -hex 24`,
   `chmod 600`).

6. **Start:** `sudo docker compose up -d` — the pull happens automatically
   and anonymously. First boot runs the DB migrations; give the app a couple
   of minutes, then visit your hostname and sign up with the
   `becomeOwnerEmailAddress` address to claim the admin account.

## ARM-specific notes

- **Redis kernel probe:** on arm64, Redis runs a check for a real
  copy-on-write kernel bug at startup. Modern kernels (Raspberry Pi OS
  current, Debian 12+) pass it silently. If Redis exits citing
  `ARM64-COW-BUG`, your kernel is genuinely affected — **upgrade the kernel**
  rather than suppressing the check; it exists to protect your data.
  (Suppression is only appropriate under qemu emulation, where the probe
  false-positives.)
- **Search** (ElasticSearch) runs natively on ARM hardware with no special
  handling. (It cannot run under qemu *emulation* — ES 8+ mandatorily
  installs a seccomp sandbox qemu-user can't provide — but that limitation
  does not exist on real ARM kernels.)
- **Performance expectations** (Pi 5): small-VPS feel. The one perceptibly
  slow spot is server-side rendering of not-yet-cached pages (Nashorn); the
  built-in Redis render cache absorbs most of it. JVM startup takes a minute
  or two.

## Current limitations

- Tags are single-arch with a `-arm64` suffix; multi-arch tags (same tag on
  every CPU) are planned via manifest stitching.
- No automatic upgrade channel — watch the packages page and re-pin.
- Images track this fork's `docker-only-build` branch (currently unmodified
  Talkyard v1.2026.004 application code + this fork's build tooling).
  Whether official upstream arm64 images ever happen is entirely upstream's
  call — nothing here is endorsed by the Talkyard project.
