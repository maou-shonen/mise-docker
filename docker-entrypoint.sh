#!/usr/bin/env sh
# Dev workspace entrypoint.
#
# Order matters: trust the workspace config first so the subsequent
# `mise install` can read .mise.toml / mise.toml / .tool-versions
# without failing on an untrusted config, then install the tools
# declared by that config, and finally exec the user's command.
#
# `set -e` ensures any failure in `mise trust` or `mise install`
# prevents the user command from running.

set -e

mise trust --all
mise install

exec "$@"
