# syntax=docker/dockerfile:1.7
#
# Public targets: base, dev, ci
#
# base: minimal Ubuntu + Mise only.
# dev:  Ubuntu 24.04 + Mise + Git + build-essential. Prepares /workspace
#       and execs the given command through docker-entrypoint.sh, which
#       runs `mise trust --all` and `mise install` before the user's
#       command so the workspace contract is satisfied.
# ci:   official Node.js LTS Debian slim + Mise + Git + build-essential.
#       Mirrors the dev toolchain on top of the upstream Node image so
#       Node and Mise are both available without runtime switches. No
#       workspace bootstrap and no entrypoint; CI invokes mise directly.

# ----------------------------------------------------------------------------
# Shared build args.
#
# MISE_VERSION and NODE_VERSION are declared as global defaults (before any
# FROM) so every stage can resolve them. CI overrides both via --build-arg
# using the values emitted by scripts/fetch-versions.sh; the global
# declaration is the source of those defaults, which avoids BuildKit's
# InvalidDefaultArgInFrom linter and the empty-substitution footgun when
# the FROM line itself interpolates one of these args.
ARG MISE_VERSION=2026.8.0
ARG NODE_VERSION=24.18.1

# ----------------------------------------------------------------------------
# mise installer stage: a slim stage that downloads the official mise binary.
# Kept separate so the runtime stages don't need the download toolchain.
FROM ubuntu:24.04 AS mise-installer
# Re-declare MISE_VERSION and TARGETARCH inside the stage so they remain
# visible to RUN commands in this stage. Defaults are intentionally omitted
# here; the global ARGs above the FROM are the source of truth.
ARG MISE_VERSION
ARG TARGETARCH

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*

# Map Docker TARGETARCH to mise asset arch suffix.
# mise assets: linux-x64, linux-arm64, linux-armv7 (musl variants are not used here).
RUN set -eux; \
  case "${TARGETARCH}" in \
    amd64)   mise_arch=x64 ;; \
    arm64)   mise_arch=arm64 ;; \
    arm)     mise_arch=armv7 ;; \
    *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
  esac; \
  url="https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${mise_arch}.tar.xz"; \
  curl -fsSL -o /tmp/mise.tar.xz "${url}"; \
  mkdir -p /tmp/mise-extract; \
  tar -xJf /tmp/mise.tar.xz -C /tmp/mise-extract; \
  install -m 0755 /tmp/mise-extract/mise/bin/mise /usr/local/bin/mise; \
  rm -rf /tmp/mise.tar.xz /tmp/mise-extract; \
  /usr/local/bin/mise --version

# ----------------------------------------------------------------------------
# base: minimal Ubuntu + Mise only.
# Runtime-neutral: no entrypoint, no WORKDIR, no toolchain. Containers
# inherit CMD ["mise"] so `docker run --rm <image>` is a no-op shell-out
# to mise, and callers can override the command at run time.
# ----------------------------------------------------------------------------
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV MISE_DATA_DIR=/mise
ENV MISE_CONFIG_DIR=/mise
ENV MISE_CACHE_DIR=/mise/cache
ENV MISE_STATE_DIR=/mise/state
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
ENV PATH=/mise/shims:$PATH

# Install only what is required to fetch ca-certs; mise itself is copied in.
# No Git, no compiler toolchain, no dev entrypoint in the base image.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=mise-installer /usr/local/bin/mise /usr/local/bin/mise

# Create the mise data, cache, and state directories up front and make them
# world-writable so an arbitrary numeric Compose user (e.g. user: "1000:1000")
# can read and write without ownership surprises. Mode 1777 (sticky) prevents
# users from removing each other's files inside the same directory.
RUN set -eux; \
  mkdir -p /mise/cache /mise/state; \
  chmod 1777 /mise /mise/cache /mise/state; \
  /usr/local/bin/mise --version

CMD ["mise"]

# ----------------------------------------------------------------------------
# dev: Ubuntu 24.04 + Mise + Git + build-essential.
# Runtime-neutral base (same Ubuntu 24.04 as `base`) so the only divergence
# from `base` is the added toolchain, the workspace bootstrap, and the
# entrypoint. Workspace is prepared by docker-entrypoint.sh before the
# user's command runs.
#
# NODE_VERSION is no longer needed here: this stage is runtime-neutral and
# installs Node via Mise rather than the upstream Node image.
# ----------------------------------------------------------------------------
FROM ubuntu:24.04 AS dev
ENV DEBIAN_FRONTEND=noninteractive
ENV MISE_DATA_DIR=/mise
ENV MISE_CONFIG_DIR=/mise
ENV MISE_CACHE_DIR=/mise/cache
ENV MISE_STATE_DIR=/mise/state
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
ENV PATH=/mise/shims:$PATH

# Git and build-essential give Mise a real toolchain to compile native
# extensions from (e.g. python-build dependencies), and let `mise install`
# succeed without missing-cc errors. ca-certificates keeps TLS fetches
# working in the same apt pass.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    build-essential \
  && rm -rf /var/lib/apt/lists/*

COPY --from=mise-installer /usr/local/bin/mise /usr/local/bin/mise
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Same world-writable /mise layout as base, plus the workspace directory.
RUN set -eux; \
  mkdir -p /mise/cache /mise/state /workspace; \
  chmod 1777 /mise /mise/cache /mise/state; \
  chmod 1777 /workspace; \
  /usr/local/bin/mise --version

WORKDIR /workspace

# No USER directive: dev runs as root by default so an arbitrary numeric
# Compose user can still mount a bind and have write access via the
# 1777 permissions above; users are free to add their own USER.

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["mise"]

# ----------------------------------------------------------------------------
# ci: official Node.js LTS Debian slim + Mise + Git + build-essential.
# Node LTS belongs here: CI workflows need a real Node runtime pinned to
# an explicit upstream version, not a Mise-installed copy whose version
# drifts per build. Mise sits on top so additional toolchains (Python,
# Go, etc.) are still installable on demand.
#
# NODE_VERSION is passed by CI (selected by scripts/fetch-versions.sh
# as the newest LTS whose `node:<version>-bookworm-slim` Docker Hub
# manifest is usable, falling back to an earlier LTS when the latest
# release's bookworm-slim manifest has not yet been fully published
# upstream) so the build is pinned to an explicit upstream version
# rather than the moving `lts-slim` alias.
# The default below is a pinned snapshot of the LTS version at the time
# this file was last updated; CI overrides it per build via
# `--build-arg NODE_VERSION` using the value emitted by
# scripts/fetch-versions.sh. The global ARG declaration before the first
# FROM is the source of that default value.
#
# No docker-entrypoint, no WORKDIR, no automatic trust/install: CI runs
# `mise` directly with explicit arguments (e.g. `mise run ci`, `mise exec`)
# inside its own working directory, which is typically the bind-mounted
# repository checkout. The explicit empty ENTRYPOINT drops the upstream
# `node` wrapper shipped with the official image so CMD isn't prepended
# with the entrypoint.
# ----------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS ci
ENV MISE_DATA_DIR=/mise
ENV MISE_CONFIG_DIR=/mise
ENV MISE_CACHE_DIR=/mise/cache
ENV MISE_STATE_DIR=/mise/state
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
ENV PATH=/mise/shims:$PATH

# Same toolchain as dev (Git + build-essential + ca-certificates) so
# `mise install` has the same capabilities here as it does in dev. The
# upstream image already ships a recent C toolchain; build-essential
# layers in gcc/make so native extensions (e.g. node-gyp, python-build
# deps) build without additional setup.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    build-essential \
  && rm -rf /var/lib/apt/lists/*

COPY --from=mise-installer /usr/local/bin/mise /usr/local/bin/mise

# World-writable /mise layout so an arbitrary numeric Compose user can
# still read and write. No /workspace: CI chooses its own working
# directory at run time.
RUN set -eux; \
  mkdir -p /mise/cache /mise/state; \
  chmod 1777 /mise /mise/cache /mise/state; \
  /usr/local/bin/mise --version

# No USER directive: ci runs as root by default for the same reason as
# dev — callers that need a non-root user can add their own USER.

# Clear the upstream `node` entrypoint so CMD isn't prepended with the
# node wrapper. CI drives mise directly via `docker run ... <image> mise ...`.
ENTRYPOINT []
CMD ["mise"]
