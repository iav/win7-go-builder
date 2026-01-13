# Docker Image for Building restic and rclone with Windows 7 Support

**[Русский](README.ru.md) | [Deutsch](README.de.md)**

## Description

Self-contained Docker image for cross-compiling [restic](https://restic.net/) and [rclone](https://rclone.org/) with **Windows 7 / Windows Server 2008 R2** support.

### Problem

Starting with Go 1.21, official Windows 7 support was dropped. Binaries built with standard Go 1.21+ won't run on Windows 7.

### Solution

This image uses [XTLS/go-win7](https://github.com/XTLS/go-win7) — a Go fork with patches to restore Windows 7 compatibility.

### Features

- **Self-contained**: can be placed in any directory, doesn't require being in the source tree
- **Auto-download**: if sources aren't found, it will download them from GitHub automatically
- **All-inclusive**: everything needed is included in the image
- **Multi-project**: supports both restic and rclone

## Quick Start

### Option 1: Fully automatic (downloads sources automatically)

```bash
# Create build directory
mkdir win7-build && cd win7-build

# Copy Dockerfile and build.sh here (or download them)
# ...

# Build the image
docker build -t win7-builder .

# Run (will download sources and build)
# -v win7-go-cache:/go — preserves Go module cache between runs
docker run --rm \
    -v $(pwd):/workspace \
    -v win7-go-cache:/go \
    win7-builder
```

Results will appear in `./output/`.

### Option 2: With existing sources

```bash
mkdir win7-build && cd win7-build

# Get sources
git clone https://github.com/restic/restic.git
git clone https://github.com/rclone/rclone.git

# Build the image
docker build -t win7-builder .

# Run
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

### Option 3: Sources in a different location

```bash
docker run --rm \
    -v /path/to/restic/sources:/workspace/restic:ro \
    -v /path/to/rclone/sources:/workspace/rclone:ro \
    -v $(pwd)/output:/workspace/output \
    win7-builder all:all
```

## Usage

### Commands (New Format: project:arch)

| Command | Description |
|---------|-------------|
| `restic:all` | Build restic for Windows 64-bit and 32-bit |
| `restic:amd64` | Build restic for Windows 64-bit only |
| `restic:386` | Build restic for Windows 32-bit only |
| `rclone:all` | Build rclone for Windows 64-bit and 32-bit |
| `rclone:amd64` | Build rclone for Windows 64-bit only |
| `rclone:386` | Build rclone for Windows 32-bit only |
| `all:all` | Build everything (restic + rclone, both architectures) |
| `all:amd64` | Build everything for 64-bit only |
| `help` | Show help |

### Commands (Legacy Format: restic only)

| Command | Description |
|---------|-------------|
| `all` | Build restic for Windows 64-bit and 32-bit (default) |
| `amd64` | Windows 64-bit only |
| `386` | Windows 32-bit only |
| `linux` | Linux 64-bit |

### Examples

```bash
# Build restic for both Windows architectures (default)
docker run --rm -v $(pwd):/workspace win7-builder

# Build restic 64-bit only
docker run --rm -v $(pwd):/workspace win7-builder restic:amd64

# Build rclone for both Windows architectures
docker run --rm -v $(pwd):/workspace win7-builder rclone:all

# Build everything
docker run --rm -v $(pwd):/workspace win7-builder all:all

# Build multiple specific targets
docker run --rm -v $(pwd):/workspace win7-builder restic:amd64 rclone:amd64
```

### Interactive mode

```bash
docker run --rm -it \
    -v $(pwd):/workspace \
    --entrypoint /bin/bash \
    win7-builder
```

## Source Detection Logic

The script searches for sources in the following order:

1. **In /workspace root** — if the mounted directory is the project repository itself
2. **In subdirectories** — `restic/`, `rclone/`, `*-master/`, `*-main/`, `src/`, `source/`
3. **In all first-level subdirectories** — if the directory has a different name

### How projects are identified

- **restic**: presence of `go.mod` with `module github.com/restic/restic`, or `VERSION` file + `cmd/restic/` directory
- **rclone**: presence of `go.mod` with `module github.com/rclone/rclone`, or `VERSION` file + `cmd/rclone/` directory

### If sources aren't found

The script attempts to download:

1. **git clone** from GitHub
2. **Archive** from GitHub releases

If both methods fail, instructions are displayed explaining what to do.

## Structure

```
docker-win7-build/
├── Dockerfile      # Image based on debian:bookworm-slim
├── build.sh        # Build script with auto-download
└── README.md       # This documentation

After building:
/workspace/
├── restic/         # restic sources (downloaded or mounted)
├── rclone/         # rclone sources (downloaded or mounted)
└── output/         # Build results
    ├── restic-v0.18.1-win7-64.exe
    ├── restic-v0.18.1-win7-32.exe
    ├── rclone-v1.69.0-win7-64.exe
    └── rclone-v1.69.0-win7-32.exe
```

Output filename format: `{project}-{version}-win7-{arch}.exe`

## Go Module Caching

To speed up subsequent builds, use a named volume for Go cache:

```bash
# First build (~2-5 minutes) — downloads all dependencies
docker run --rm -v $(pwd):/workspace -v win7-go-cache:/go win7-builder all:all

# Subsequent builds (~6-30 seconds) — uses cache
docker run --rm -v $(pwd):/workspace -v win7-go-cache:/go win7-builder all:all
```

Without the `-v win7-go-cache:/go` volume, dependencies will be downloaded every time.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSPACE` | `/workspace` | Working directory |
| `GOPATH` | `/go` | Go cache path (mount volume here) |
| `RESTIC_VERSION` | *(latest release)* | restic version (tag, branch, or commit) |
| `RCLONE_VERSION` | *(latest release)* | rclone version (tag, branch, or commit) |
| `RESTIC_GIT_URL` | `https://github.com/restic/restic.git` | URL for git clone (restic) |
| `RCLONE_GIT_URL` | `https://github.com/rclone/rclone.git` | URL for git clone (rclone) |
| `CGO_ENABLED` | `0` | Static linking |

## Building a Specific Version/Tag

### Using environment variables (recommended)

```bash
# Build specific versions
docker run --rm \
    -v $(pwd):/workspace \
    -v win7-go-cache:/go \
    -e RESTIC_VERSION=v0.17.3 \
    -e RCLONE_VERSION=v1.68.2 \
    win7-builder all:all

# Build from a specific commit
docker run --rm \
    -v $(pwd):/workspace \
    -e RESTIC_VERSION=abc1234 \
    win7-builder restic:amd64

# Build latest versions (default behavior)
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

### Using local sources

```bash
# Clone with a specific tag
git clone --branch v0.17.3 --depth 1 https://github.com/restic/restic.git
git clone --branch v1.68.2 --depth 1 https://github.com/rclone/rclone.git

# Build
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

## Compatibility Check

Built binaries are marked as compatible with Windows 6.01 (Windows 7):

```bash
file output/restic-v0.18.1-win7-64.exe
# PE32+ executable for MS Windows 6.01 (console), x86-64

file output/rclone-v1.69.0-win7-64.exe
# PE32+ executable for MS Windows 6.01 (console), x86-64
```

## Updating Go SDK

To use a different version of patched Go:

```bash
docker build \
    --build-arg GO_WIN7_VERSION=1.25.5 \
    --build-arg GO_WIN7_TAG=patched-1.25.5 \
    -t win7-builder .
```

Available versions: https://github.com/XTLS/go-win7/releases

## Technical Details

- **Base image**: `debian:bookworm-slim`
- **Go version**: 1.25.5 (patched for Windows 7)
- **Image size**: ~350 MB
- **Output files**: compatible with Windows 7 (PE for Windows 6.01)

## Troubleshooting

### "Failed to find or download sources"

1. Check internet access in the container
2. Download sources manually:
   ```bash
   git clone https://github.com/restic/restic.git
   git clone https://github.com/rclone/rclone.git
   ```
3. Mount the sources directory

### "Permission denied" when writing results

Make sure the `/workspace/output` directory is writable:
```bash
mkdir -p output && chmod 777 output
```

## Links

- [restic](https://restic.net/) — backup program
- [rclone](https://rclone.org/) — cloud storage sync tool
- [XTLS/go-win7](https://github.com/XTLS/go-win7) — patched Go for Windows 7
- [Discussion on Windows 7 support removal in Go](https://github.com/golang/go/issues/57003)
