#!/usr/bin/env bash

# Run from the project root directory.
#
# Builds the app server production image. The unzip/split/layout staging that
# used to happen here on the host now runs inside the Dockerfile's dist_prep
# stage [appsv_build_image] — this script only captures git build-info (kept
# out of the Docker context so .git needn't be sent to the daemon) and runs
# `docker build`.
#
# Prereqs (both produced in containers by the prod build pipeline):
#   target/universal/talkyard-server-<version>.zip   from:  s/d-cli dist
#   images/app/assets/                               from:  s/d-gulp build_release_dont_clean_before

set -e # exit on any error.
set -x

version="`cat version.txt | sed s/WIP/SNAPSHOT/`"
reg_org=`sed -nr 's/DOCKER_REG_ORG=([a-zA-Z0-9\._-]*).*/\1/p' .env`

# ( &> redirects both stderr and stdout.)
rm -fr target/build-info
mkdir -p target/build-info
date --utc --iso-8601=seconds > target/build-info/docker-image-build-date.txt
git rev-parse HEAD &> target/build-info/git-revision.txt
git log --oneline -n100 &> target/build-info/git-log-oneline.txt
git status &> target/build-info/git-status.txt
git diff &> target/build-info/git-diff.txt
git describe --tags &> target/build-info/git-describe-tags.txt
# This fails if there is no tag, so disable exit-on-error.
set +e
git describe --exact-match --tags &> target/build-info/git-describe-exact-tags.txt
set -e

img_tag="$reg_org/talkyard-app:latest"
docker build \
    --tag=$img_tag \
    --file images/app/Dockerfile.prod \
    --build-arg TALKYARD_VERSION=$version \
    .

echo "Image tag: $img_tag"
