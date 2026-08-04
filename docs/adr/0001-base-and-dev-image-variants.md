# Base, dev, and ci image variants

Status: accepted

The final public Dockerfile targets are `base`, `dev`, and `ci`. The `node` tag is retained as a backward-compatible alias for the `ci` image, not a fourth target.

- `base` is a minimal Ubuntu 24.04 image with only Mise — a neutral
  foundation that imposes no workspace, runtime, or tooling assumptions.
- `dev` is a Compose-first workspace on Ubuntu 24.04 with Mise, Git, and
  `build-essential`. Its entrypoint runs `mise trust --all` (which
  trusts every config Mise can discover from the current working
  directory — the workspace, its subdirectories, and its parents — not
  narrowly only the mounted workspace) and then `mise install` before
  exec-ing the user's command. It is **runtime-neutral**: no Node,
  Python, Go, or other language runtime is preinstalled; whatever tools
  the workspace needs are installed by Mise from the workspace
  configuration.
- `ci` is a native-command CI toolchain based on the official
  `node:${NODE_VERSION}-bookworm-slim` (Debian bookworm slim) with
  Mise, Git, and `build-essential` layered on top. It has no entrypoint,
  no `WORKDIR`, and no implicit `mise trust` / `mise install`; the
  calling CI job is the source of truth for trust, install, and the
  command flow. The `:node` tag points to this exact same image and
  contract for backward compatibility; it is not an independent target.

The public Dockerfile target set remains exactly `base`, `dev`, and `ci`; consumers may use `:node` only as the compatibility tag for `:ci`.

## History

The initial plan exposed `base`, `dev`, and `ci` variants. `ci` was
then removed from the public set on the grounds that the original
Node-bearing CI variant duplicated responsibilities with `dev` and
that CI workflows should run explicitly on `base` or `dev` rather than
on a third variant. While that decision was in force, `dev` was
rebuilt on the official Node LTS Debian slim base so that Compose-first
workspaces had a usable runtime out of the box.

That arrangement was reconsidered: `dev`'s automatic workspace
bootstrap (entrypoint-driven `mise trust --all` and `mise install`)
and CI's need for a native-command environment with no implicit setup
are different contracts, and forcing CI onto `dev` meant either
fighting the entrypoint or carrying Node in a variant whose contract
was "prepare the workspace and run the user's command." `ci` was
therefore reintroduced as a separate variant, and the original
Node-on-CI rationale, which had never gone away, was restored with it.
At the same time `dev` returned to a runtime-neutral Ubuntu 24.04 base
— Node is no longer part of `dev`.

## Why Node belongs to `ci`, not `dev`

Node's original inclusion in this project was tied to the CI use case:
CI jobs needed Node available without an extra `mise install` step.
That rationale did not survive into `dev`'s redesign, which is a
Compose-first workspace where Mise installs whatever tools the
workspace configuration declares — including Node, when a workspace
asks for it. Carrying Node in `dev` would have made `dev` non-neutral
about the workspace's runtime stack and would have duplicated a
capability CI already needs.

Reintroducing `ci` with Node restored the original CI rationale at the
right level of abstraction: a CI toolchain where Node is part of the
environment, the entrypoint is absent, and the calling job controls
the command flow. `dev` stays runtime-neutral and aligns with its
workspace-preparation contract.

## Considered Options

- Keep `ci` removed and require CI to use `dev`: rejected because
  `dev`'s entrypoint-driven `mise trust --all` and `mise install` are
  a workspace-preparation contract that conflicts with CI's
  native-command, explicit-trust/install contract. Forcing CI onto
  `dev` also requires carrying Node in `dev`, which conflicts with
  `dev`'s runtime-neutral workspace contract.
- Make every variant inherit from the same Ubuntu base: rejected
  because `ci` benefits from the official Node LTS Debian slim base
  (a stable, narrowly scoped Node runtime), while `base` and `dev`
  benefit from a neutral Ubuntu 24.04 foundation. A single shared
  base would either drag Node into `base` and `dev` or drag the
  workspace preparation contract into `ci`.

## Consequences

`dev` continues to prepare the workspace automatically: when it starts,
it runs `mise trust --all` (which trusts every config Mise can
discover from the workspace's working directory) and then `mise
install`, then exec-s the user's command through Mise shims. With
`MISE_DATA_DIR=/mise`, tool installations live under `/mise/installs`
at the container scope; the entire `/mise` tree (data, cache, state)
is ephemeral when the container is removed and persists only if
`/mise` (or a sub-path such as `/mise/cache`) is bind-mounted.

`ci` performs no implicit setup. Each CI step (or the job's command
sequence) explicitly decides when to `mise trust --all`, when to
`mise install`, and which commands to run. Node is available because
it is part of the CI image, not because any implicit step installs it.

`base` imposes no contract beyond providing Mise; users build the rest
of their environment as they see fit.