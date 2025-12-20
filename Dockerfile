FROM ubuntu:latest AS base

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV MISE_DATA_DIR="/mise"
ENV MISE_CONFIG_DIR="/mise"
ENV MISE_CACHE_DIR="/mise/cache"
ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
ENV PATH="/mise/shims:$PATH"

# Install dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  curl \
  build-essential \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install mise
RUN curl https://mise.run | sh

# ============================================
# Node variant: base + Node.js LTS
# ============================================
FROM base AS node

# Install Node.js LTS using mise
RUN mise use --global node@lts \
  && mise install node@lts
