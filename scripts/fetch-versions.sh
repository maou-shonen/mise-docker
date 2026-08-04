#!/usr/bin/env bash
# Fetch latest mise and Node.js LTS versions, output to GITHUB_OUTPUT.
# Requires: curl, jq
# Environment: GH_TOKEN (GitHub token for authenticated API requests)
set -euo pipefail

# Retry wrapper: handles both HTTP errors and curl transport failures.
# Up to 3 attempts with exponential backoff (5s, 10s between attempts).
fetch_with_retry() {
  local url="$1"
  shift
  local max_retries=3
  local attempt=0
  local wait=5
  local body_file
  body_file=$(mktemp)
  trap "rm -f '$body_file'" RETURN

  while [ "$attempt" -lt "$max_retries" ]; do
    local curl_exit=0
    local HTTP_CODE
    : > "$body_file"
    HTTP_CODE=$(curl -sS --connect-timeout 10 --max-time 30 \
      -o "$body_file" -w '%{http_code}' "$@" "$url") || curl_exit=$?

    if [ "$curl_exit" -eq 0 ] && [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
      cat "$body_file"
      return 0
    fi

    attempt=$((attempt + 1))
    if [ "$curl_exit" -ne 0 ]; then
      echo "::warning::curl failed (exit ${curl_exit}) for ${url}, attempt ${attempt}/${max_retries}" >&2
    else
      echo "::warning::HTTP ${HTTP_CODE} from ${url}, attempt ${attempt}/${max_retries}" >&2
    fi

    if [ "$attempt" -lt "$max_retries" ]; then
      echo "::warning::Retrying in ${wait}s..." >&2
      sleep "$wait"
      wait=$((wait * 2))
    fi
  done

  echo "::error::Failed to fetch ${url} after ${max_retries} attempts" >&2
  [ -s "$body_file" ] && cat "$body_file" >&2
  return 1
}

# Node.js LTS selection.
#
# The newest LTS version published to https://nodejs.org/dist/index.json is
# not always present on Docker Hub — most commonly a release is uploaded to
# nodejs.org before the corresponding `node:<version>-bookworm-slim` multi-arch
# manifest is published to Docker Hub, leaving it as an empty index that
# breaks the Dockerfile's `FROM node:${NODE_VERSION}-bookworm-slim` (the
# manifest lists no platforms, so `docker pull` cannot resolve linux/amd64 or
# linux/arm64). Probe candidates in descending version order against the
# Docker Hub Registry v2 API and pick the newest whose manifest list is
# populated and contains at least the intended published platforms.
#
# Requirements: curl, jq. No Docker CLI dependency.
select_node_version() {
  local index_json="$1"

  # Emit candidate versions in newest-first order. The index is already
  # newest-first, so take items where lts != false and strip the leading "v".
  # Strict numeric semver (X.Y.Z, no suffixes) is required before any string
  # is interpolated into a URL — nodejs.org is trusted, but we never let an
  # upstream value break out of the path component. Always returns 0 so
  # callers don't trip set -e on the no-LTS-present edge case (the empty
  # stream is still a valid result that the loop will fall through to the
  # clear "no candidate" failure path).
  # The trailing `|| true` guards against `awk` returning 1 when nothing
  # matches the semver filter — under `set -o pipefail` that would otherwise
  # propagate as a subshell failure inside the function body.
  jq -r '[.[] | select(.lts != false)][].version' <<<"$index_json" \
    | sed 's/^v//' \
    | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/' \
    || true
  return 0
}

# Fetch a Docker Hub Registry v2 bearer token for the public library/node
# repository. Acquiring one per probe is cheap (registry tokens are
# per-request, the token endpoint has a generous rate limit, and the only
# constrained budget is the manifest endpoint at 100/hr/IP) and isolates
# each candidate from a stale token mid-script.
fetch_registry_token() {
  fetch_with_retry \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/node:pull" \
    | jq -r '.token // empty'
}

# Returns 0 when the `node:<version>-bookworm-slim` manifest exists, is a
# manifest list / image index, and advertises both linux/amd64 and linux/arm64.
# Otherwise returns non-zero. Stdout is intentionally quiet so the caller
# controls the user-facing log lines.
node_manifest_has_intended_platforms() {
  local version="$1"
  local token
  # `|| true` is intentional: under `set -e` an `EOL` on `:=` from a failed
  # subshell would abort the function before the explicit guard below, and
  # the explicit guard still rejects empty/null tokens cleanly.
  token=$(fetch_registry_token || true)
  if [ -z "${token}" ] || [ "${token}" = "null" ]; then
    echo "::error::Failed to acquire Docker Hub registry token for ${version}" >&2
    return 1
  fi
  local body
  local fetch_status

  # Accept every manifest type the registry may legitimately return so a
  # populated list/index resolves rather than 4xx-ing on a narrow Accept.
  # Single-arch manifests are intentionally rejected — the project builds a
  # linux/amd64 + linux/arm64 matrix and a single-arch image would break it.
  #
  # The `set +e` / `set -e` brackets are load-bearing: under `set -e`, a
  # bare `body=$(fetch_with_retry ...)` would abort the whole script if
  # `fetch_with_retry` exhausts its retries (5xx, 404, network blip). We
  # want a non-zero return so the caller can skip THIS candidate and the
  # loop can fall through to the final "no candidate" failure path.
  set +e
  body=$(fetch_with_retry \
    "https://registry-1.docker.io/v2/library/node/manifests/${version}-bookworm-slim" \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json')
  fetch_status=$?
  set -e
  if [ "$fetch_status" -ne 0 ]; then
    echo "::warning::Manifest fetch failed for node=${version} (status ${fetch_status}); skipping candidate" >&2
    return 1
  fi
  if [ -z "$body" ]; then
    echo "::warning::Empty manifest body for node=${version}; skipping candidate" >&2
    return 1
  fi

  jq -e '
    (.mediaType == "application/vnd.docker.distribution.manifest.list.v2+json"
     or .mediaType == "application/vnd.oci.image.index.v1+json")
    and (.manifests | type == "array")
    and (.manifests | length > 0)
    and ([.manifests[]?.platform | select(.os == "linux" and .architecture == "amd64")] | length) > 0
    and ([.manifests[]?.platform | select(.os == "linux" and .architecture == "arm64")] | length) > 0
  ' <<<"$body" >/dev/null
}

# GitHub release tags and the Node distribution index both carry a leading
# "v" (e.g. "v2026.8.1"). Strip it so downstream consumers can prepend their
# own prefix (the Dockerfile's release URL template adds "v" itself) and the
# versions-hash cache key stays stable across prefix-vs-no-prefix changes.
MISE_VERSION=$(fetch_with_retry \
  "https://api.github.com/repos/jdx/mise/releases/latest" \
  -H "Authorization: Bearer ${GH_TOKEN}" | jq -r '.tag_name' | sed 's/^v//')
if [ -z "${MISE_VERSION}" ] || [ "${MISE_VERSION}" = "null" ]; then
  echo "::error::Failed to fetch mise version"
  exit 1
fi

NODE_INDEX_JSON=$(fetch_with_retry "https://nodejs.org/dist/index.json")

NODE_VERSION=""
while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  if node_manifest_has_intended_platforms "$candidate"; then
    NODE_VERSION="$candidate"
    echo "::notice::Selected node=${NODE_VERSION} (verified linux/amd64+linux/arm64 on registry)" >&2
    break
  else
    echo "::notice::Skipping node=${candidate} (manifest missing or lacks intended platforms)" >&2
  fi
done < <(select_node_version "$NODE_INDEX_JSON")

if [ -z "${NODE_VERSION}" ]; then
  echo "::error::No LTS Node version has a populated node:<v>-bookworm-slim manifest on Docker Hub" >&2
  exit 1
fi

HASH="${MISE_VERSION}-${NODE_VERSION}"
echo "mise=${MISE_VERSION}" >> "$GITHUB_OUTPUT"
echo "node=${NODE_VERSION}" >> "$GITHUB_OUTPUT"
echo "versions-hash=${HASH}" >> "$GITHUB_OUTPUT"
echo "::notice::mise=${MISE_VERSION}, node=${NODE_VERSION}, hash=${HASH}"
