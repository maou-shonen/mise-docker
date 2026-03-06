# mise-docker

[![Build and Publish Docker Image](https://github.com/maou-shonen/mise-docker/actions/workflows/publish.yml/badge.svg)](https://github.com/maou-shonen/mise-docker/actions/workflows/publish.yml)
[![:latest](https://img.shields.io/github/v/release/maou-shonen/mise-docker?label=%3Alatest&sort=date)](https://github.com/maou-shonen/mise-docker/releases/latest)

Docker images based on Ubuntu Latest with [Mise](https://mise.jdx.dev/) pre-installed. Available in two variants:

> [!NOTE]
> The GHCR package has been renamed from `ghcr.io/maou-shonen/mise-docker` to `ghcr.io/maou-shonen/mise`. Please use the new name.

## Variants

### `:latest` - Mise Only
Base image with only Mise installed.

```bash
docker pull ghcr.io/maou-shonen/mise:latest
docker run -it ghcr.io/maou-shonen/mise:latest
```

### `:node` - Mise + Node.js LTS
Image with Mise and Node.js LTS pre-installed.

```bash
docker pull ghcr.io/maou-shonen/mise:node
docker run -it ghcr.io/maou-shonen/mise:node
```

## Features

- **Base Image**: Ubuntu Latest
- **Mise**: Latest version
- **Node.js** (node variant): LTS version (installed via Mise)
- **Daily Builds**: Automatically built and published daily via GitHub Actions

## Usage Examples

### Verify Mise Installation

```bash
docker run --rm ghcr.io/maou-shonen/mise:latest mise --version
```

### Use Node.js

```bash
docker run --rm ghcr.io/maou-shonen/mise:node mise exec -- node --version
docker run --rm ghcr.io/maou-shonen/mise:node mise exec -- npm --version
```

### Install Additional Tools with Mise

```bash
docker run -it ghcr.io/maou-shonen/mise:latest
# Inside container:
mise use python@latest
mise install python@latest
mise exec -- python --version
```

## Tags

### Base Variant (`:latest`)
- `latest`: Latest build
- `YYYYMMDD`: Daily build tag (e.g., `20251220`)
- `YYYYMMDD-<sha>`: Build with commit SHA

### Node Variant (`:node`)
- `node`: Latest build with Node.js
- `YYYYMMDD-node`: Daily build tag with Node.js
- `YYYYMMDD-node-<sha>`: Build with commit SHA and Node.js

## Building Locally

```bash
# Build base variant (mise only)
docker build --target base -t mise-docker:latest .

# Build node variant (mise + node)
docker build --target node -t mise-docker:node .
```
