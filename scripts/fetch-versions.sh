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

# mise: fetch latest release tag from GitHub API (authenticated to avoid rate limits)
MISE_VERSION=$(fetch_with_retry \
  "https://api.github.com/repos/jdx/mise/releases/latest" \
  -H "Authorization: Bearer ${GH_TOKEN}" | jq -r '.tag_name')
if [ -z "${MISE_VERSION}" ] || [ "${MISE_VERSION}" = "null" ]; then
  echo "::error::Failed to fetch mise version"
  exit 1
fi

# Node.js LTS: fetch from official API
NODE_VERSION=$(fetch_with_retry \
  "https://nodejs.org/dist/index.json" | jq -r '[.[] | select(.lts != false)][0].version')
if [ -z "${NODE_VERSION}" ] || [ "${NODE_VERSION}" = "null" ]; then
  echo "::error::Failed to fetch Node.js LTS version"
  exit 1
fi

HASH="${MISE_VERSION}-${NODE_VERSION}"
echo "mise=${MISE_VERSION}" >> "$GITHUB_OUTPUT"
echo "node=${NODE_VERSION}" >> "$GITHUB_OUTPUT"
echo "versions-hash=${HASH}" >> "$GITHUB_OUTPUT"
echo "::notice::mise=${MISE_VERSION}, node=${NODE_VERSION}, hash=${HASH}"
