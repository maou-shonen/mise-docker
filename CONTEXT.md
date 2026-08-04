# mise Docker Images

This project provides Docker image variants centered on Mise and organized by usage context. The public Dockerfile targets are `base`, `dev`, and `ci`; `node` is a backward-compatible image tag alias for `ci`, not an independent target.

## Image Variants

**Base**:
The minimal, neutral shared foundation that provides Mise.
_Avoid_: Dev, Development, Developer

**Dev**:
The development image variant, providing a Compose-first workspace and workspace preparation behavior.
_Avoid_: Development, Developer

**CI**:
The CI toolchain variant, also available through the compatibility tag `:node`, provides the official Node.js LTS, Mise, Git, and `build-essential`. `:ci` and `:node` are the same image and share the CI contract: no entrypoint, no `WORKDIR`, and no implicit trust, install, or other workspace preparation.

**Compose-first workspace**:
A workspace designed to run development commands after the project directory is mounted, with minimal Compose configuration.

**Workspace preparation**:
Before running the user's command, the Dev workspace prepares its configuration and required tools; if preparation fails, the command is not run.

**Workspace trust**:
The Dev entrypoint runs `mise trust --all` from the workspace's working directory. That flag trusts every config Mise can discover from the current working directory — the workspace's own config and any configs in its subdirectories (and parents) — not narrowly only the top-level mounted workspace. The Dev variant intentionally widens trust to that discovered set so nested subprojects do not block bootstrap.

**Workspace**:
The project file scope that the developer gives the Dev image to process; it may contain one project or multiple related subprojects.

**Container-scoped installs**:
With `MISE_DATA_DIR=/mise`, Mise tool installations live under `/mise/installs` and are shared across the container, not workspace-local. The entire `/mise` tree (data, cache, state) is at container scope and is ephemeral when the container is removed unless `/mise` (or a sub-path of it) is bind-mounted.
_Avoid_: Workspace-local installs

**Mount-persisted mise tree**:
When `/mise` (or a sub-path of it such as `/mise/cache`) is bind-mounted from the host, the corresponding Mise data persists across container removals. Mounting a sub-path persists only that slice; tool installs at `/mise/installs` persist only when `/mise` or `/mise/installs` is mounted.

**CI toolchain**:
The CI image variant (also tagged `:node` for backward compatibility) exposes a native-command environment with official Node.js LTS, Mise, Git, and `build-essential` preinstalled but performs no implicit workspace preparation; the calling CI job is the source of truth for trust, install, and the command flow.

**Shim**:
A command entry point provided by Mise that selects tool versions according to the current workspace configuration; a workspace-selected version takes precedence over the runtime preinstalled in the image.
_Avoid_: System binary, fixed runtime path