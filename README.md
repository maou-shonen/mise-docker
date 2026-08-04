# mise-docker

[![Build and Publish Docker Image](https://github.com/maou-shonen/mise-docker/actions/workflows/publish.yml/badge.svg)](https://github.com/maou-shonen/mise-docker/actions/workflows/publish.yml)
[![:latest](https://img.shields.io/github/v/release/maou-shonen/mise-docker?label=%3Alatest&sort=date)](https://github.com/maou-shonen/mise-docker/releases/latest)

Docker images with [Mise](https://mise.jdx.dev/) pre-installed. The public Dockerfile targets are `base`, `dev`, and `ci`; available image variants are:

> [!NOTE]
> The GHCR package has been renamed from `ghcr.io/maou-shonen/mise-docker` to `ghcr.io/maou-shonen/mise`. Please use the new name.

## Variants

### `:latest` — `base` (Mise only)

Minimal Ubuntu 24.04 image with only Mise installed. Use as a neutral foundation.

```bash
docker pull ghcr.io/maou-shonen/mise:latest
# The base image has CMD ["mise"] and no entrypoint, so pass a
# command explicitly. To open an interactive shell, override the
# entrypoint:
docker run -it --rm --entrypoint bash ghcr.io/maou-shonen/mise:latest
```

### `:dev` — `dev` (Compose-first workspace)
The `dev` variant is a runtime-neutral workspace image on Ubuntu 24.04
with Mise, Git, and `build-essential`. The workspace is mounted at
`/workspace`; the dev entrypoint runs `mise trust --all` (which trusts
every config Mise can discover from the workspace's working directory — the workspace, its
subdirectories, and its parents — not narrowly only the mounted
workspace) and then `mise install` before exec-ing the user's command,
so a single `docker compose run` starts a prepared workspace with no
further setup. **No language runtime is preinstalled** — any Node,
Python, Go, Rust, etc. that the workspace needs is installed by Mise
from the workspace configuration.

```bash
docker pull ghcr.io/maou-shonen/mise:dev
docker run -it -v "$PWD":/workspace ghcr.io/maou-shonen/mise:dev
```

### `:ci` — `ci` (CI toolchain with Node)

CI toolchain based on the official `node:${NODE_VERSION}-bookworm-slim`
(Debian bookworm slim) with Mise, Git, and `build-essential` layered on
top. **Includes Node.js** — the resolver in
`scripts/fetch-versions.sh` picks the newest LTS whose
`node:<version>-bookworm-slim` Docker Hub manifest is usable, falling
back to an earlier LTS when the latest release's bookworm-slim manifest
has not yet been fully published upstream. Node belongs here, not in
`dev`, because its original inclusion was tied to the CI use case. No
entrypoint, no `WORKDIR`, and no implicit `mise trust` / `mise install`;
CI jobs run explicit commands and explicitly control when to trust and
install.


### `:node` — compatibility alias for `:ci`
`:node` is a backward-compatible image tag for the same CI image as `:ci`, not a separate Dockerfile target. It provides the official Node.js LTS, Mise, Git, and `build-essential`, with the same CI contract: no entrypoint, no `WORKDIR`, and no automatic `mise trust` or `mise install`. Use `:ci` for new references; `:node` remains available for existing consumers.

```bash
docker pull ghcr.io/maou-shonen/mise:node
docker run --rm ghcr.io/maou-shonen/mise:node node --version
```

## Features

- **`base` variant**: Ubuntu 24.04 with Mise only — neutral foundation.
- **`dev` variant**: Ubuntu 24.04 with Mise, Git, and `build-essential`.
  Runtime-neutral — no Node, no Python, no Go. The workspace is mounted
  at `/workspace`; the entrypoint runs `mise trust --all` (which trusts
  every config Mise can discover from the workspace's working directory,
  not narrowly only the mounted workspace) and then `mise install`
  before exec-ing the user's command. With `MISE_DATA_DIR=/mise`, tool
  installations live under `/mise/installs` at the container scope; the
  whole `/mise` tree is ephemeral when the container is removed and
  persists only if `/mise` (or a sub-path) is bind-mounted.
- **`ci` variant (also available as the backward-compatible `:node` tag)**: Official `node:${NODE_VERSION}-bookworm-slim` with
  Mise, Git, and `build-essential` layered on top. Includes Node.js LTS
  (provided by the official Node base image, not installed via Mise).
  Both tags refer to the same CI image and have no entrypoint, no `WORKDIR`,
  and no implicit trust/install — CI jobs run explicit commands.
- **Mise version**: pinned per build from the latest upstream release
  via `--build-arg MISE_VERSION` for all three variants.
- **Node.js version (`ci` variant)**: pinned per build to the newest
  LTS whose `node:<version>-bookworm-slim` Docker Hub manifest is
  usable, with fallback to an earlier LTS when the latest release's
  bookworm-slim manifest has not yet been fully published upstream
  (selected via `--build-arg NODE_VERSION`).

## Usage Examples

### Verify Mise Installation

```bash
docker run --rm ghcr.io/maou-shonen/mise:latest mise --version
```

### Use Node.js (`ci` variant; `:node` is a compatibility alias)

```bash
docker run --rm ghcr.io/maou-shonen/mise:ci node --version
docker run --rm ghcr.io/maou-shonen/mise:node npm --version
```

### Install Additional Tools with Mise (`base` or `dev`)

The base image's `CMD` is `mise` and there is no entrypoint, so pass

```bash
# One-shot: declare, install, and run a tool in a single invocation
docker run --rm \
  -v "$PWD":/workspace -w /workspace \
  ghcr.io/maou-shonen/mise:latest \
  sh -c "mise use python@latest && mise install python@latest && mise exec -- python --version"

# Or open a shell inside the container
docker run -it --rm --entrypoint bash ghcr.io/maou-shonen/mise:latest
# Inside the shell:
# mise use python@latest
# mise install python@latest
# mise exec -- python --version
```

### CI Usage (`ci` variant)

The `ci` variant does not run any implicit setup. CI jobs explicitly
control trust, install, and the command flow:

> [!WARNING]
> `mise trust --all` trusts every Mise config it can discover from the
> working directory — the workspace itself, its parent directories,
> and its subdirectories, not narrowly only the workspace you mounted.
> A trusted mise config can run arbitrary code through `tasks`, `hooks`,
> `env`, and inline templates during `mise install` or any later
> `mise exec`/`mise run`. Only run the flow below on reviewed sources
> you trust, or replace `--all` with an explicit allowlist that names
> exactly the config files you intend to trust.

```bash
docker run --rm \
  -v "$PWD":/work \
  -w /work \
  ghcr.io/maou-shonen/mise:ci \
  sh -c "mise trust --all && mise install && mise run build && mise exec -- npm test"
```

In a GitHub Actions step the same flow looks like:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/maou-shonen/mise:ci
    steps:
      - uses: actions/checkout@v6
      - run: mise trust --all
      - run: mise install
      - run: mise run build
      - run: mise exec -- npm test
```

Because `ci` has no `WORKDIR` and no entrypoint, the job's
`working-directory` (or `-w`) and each command are fully under the
job's control.

Tags correspond to the three public Dockerfile targets (`base`, `dev`, and `ci`). The `:node` tag is a backward-compatible alias of `:ci`, not a fourth target; both tags refer to the same CI image.

### `base` variant (`:latest`)

- `latest`: latest build (from `type=raw`)
- `YYYYMMDD-latest`: daily build tag (e.g., `20251220-latest`)
- `YYYYMMDD-latest-<sha>`: build with commit SHA (e.g., `20251220-latest-abcdef0`)

### `dev` variant (`:dev`)

- `dev`: latest build of the dev image (Mise + Git + build-essential on Ubuntu 24.04)
- `YYYYMMDD-dev`: daily build tag of the dev image
- `YYYYMMDD-dev-<sha>`: build of the dev image with commit SHA

### `ci` variant (`:ci`)

- `ci`: latest build of the ci image (Node LTS + Mise + Git + build-essential)
- `YYYYMMDD-ci`: daily build tag of the ci image
- `YYYYMMDD-ci-<sha>`: build of the ci image with commit SHA

The compatibility tag `node` is a raw alias for the same latest CI image as `ci`:

- `node`: backward-compatible alias for the latest CI image


## Local Builds

```bash
# base variant (mise only, on Ubuntu 24.04)
docker build --target base -t mise-docker:latest .

# dev variant (runtime-neutral workspace on Ubuntu 24.04 + mise + git + build-essential)
docker build --target dev -t mise-docker:dev .

# ci target (official Node LTS + mise + git + build-essential)
docker build --target ci -t mise-docker:ci .
# `node` is a compatibility tag for the same ci target; do not build a node target.
docker tag mise-docker:ci mise-docker:node
```

## Minimal Compose Example (`dev`)

The `dev` image is designed for Compose. The minimal service below
mounts the current project directory as the workspace. The image's
`CMD` is `mise`, and its entrypoint (`/usr/local/bin/docker-entrypoint.sh`)
runs `mise trust --all` (which trusts every config Mise can discover
from `/workspace`) and then `mise install` before `exec`-ing the
command.

### Minimal service

```yaml
services:
  dev:
    image: ghcr.io/maou-shonen/mise:dev
    working_dir: /workspace
    volumes:
      - .:/workspace
```

Run it:

```bash
# Default: image CMD (mise) runs in the prepared workspace
docker compose run --rm dev

# Override the command per invocation
docker compose run --rm dev mise run build
docker compose run --rm dev mise exec -- my-tool
# Interactive shell inside the prepared workspace
docker compose run --rm dev bash
```

### Optional additions

The lines below are **not part of the minimal contract**; add them when
they solve a problem you actually have.

```yaml
services:
  dev:
    image: ghcr.io/maou-shonen/mise:dev
    working_dir: /workspace
    volumes:
      # Persist Mise data across containers by bind-mounting the
      # container's /mise tree. /mise holds installs (/mise/installs),
      # cache (/mise/cache), and state; mounting it keeps installed
      # tools and plugin state between container removals. Safe to
      # omit — the tree is recreated automatically when absent and
      # the whole /mise layout is then ephemeral with the container.
      - ${HOME}/.cache/mise:/mise
    user: "${UID:-1000}:${GID:-1000}"
    # Useful when running as an arbitrary numeric Compose user: many tools
    # (npm, pip, cargo, …) write caches under $HOME, and the default $HOME
    # may not be writable by that user. Point $HOME at a path the container
    # owns (here, /tmp) to keep those tools happy without bind-mounting
    # a host home directory.
    environment:
      HOME: /tmp
```

Notes:

- **Runtime-neutral**: the `dev` variant does not preinstall Node, Python,
  Go, or any other language runtime. Whatever tools the workspace needs
  are installed by Mise from the workspace configuration.
- **Ephemeral installs**: with `MISE_DATA_DIR=/mise`, tool installations
  live under `/mise/installs` and are shared across the container, not
  workspace-local. The whole `/mise` tree is ephemeral when the
  container is removed; bind-mounting `/mise` (or a sub-path such as
  `/mise/cache`) is what persists data across containers. Re-running
  `mise install` (or letting the entrypoint prepare the workspace)
  reproduces the tree when nothing is mounted.
- **Host cache**: the optional `/mise` bind mount persists Mise data
  (installs, cache, state) across containers. It improves resolution
  and lookup cost and also keeps installed tools available between
  container removals; it is the recommended mount when the cache alone
  is not enough. Mounting only `/mise/cache` improves resolution and
  lookup cost but does not replace tool installation.
- **UID/GID**: setting `user: "${UID:-1000}:${GID:-1000}"` keeps files
  written by the container owned by your host user. Adjust the defaults if
  your host UID/GID differ. When combined with the entrypoint's world-
  writable `/mise` layout, this works for any numeric host UID/GID.
- **HOME for arbitrary numeric users**: setting `HOME: /tmp` is helpful
  when `user:` overrides the container UID and tools that write to `$HOME`
  (mise state in some configurations, plus any tool that uses `$HOME`
  for its own cache) would otherwise hit a path they cannot write to. It
  is not required by Mise itself (mise data lives under `/mise`); it is
  a defensive choice for arbitrary Compose users.
- **Command customization**: replace `command` in `compose.yaml`, or pass
  arguments after the service name (see the `docker compose run` examples).
  With no `command:` and no override, the image's default `CMD` runs.