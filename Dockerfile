# =============================================================================
# Dockerfile for building restic and rclone with Windows 7 support
# =============================================================================
#
# Self-contained image for cross-compiling restic and rclone with Windows 7 support.
# Can be placed in any directory — automatically finds or downloads sources.
#
# Uses patched Go SDK (XTLS/go-win7) since official Go 1.21+ dropped Windows 7 support.
#
# Sources:
#   - Patched Go: https://github.com/XTLS/go-win7
#   - Restic: https://github.com/restic/restic
#   - Rclone: https://github.com/rclone/rclone
# =============================================================================

FROM debian:bookworm-slim

LABEL maintainer="win7-builder"
LABEL description="Cross-compilation environment for building restic and rclone with Windows 7 support"
LABEL go.version="1.25.5-win7-patched"
LABEL source.go-win7="https://github.com/XTLS/go-win7"
LABEL source.restic="https://github.com/restic/restic"
LABEL source.rclone="https://github.com/rclone/rclone"

# Patched Go SDK version
ARG GO_WIN7_VERSION=1.25.5
ARG GO_WIN7_TAG=patched-1.25.5

# Repository URLs (for auto-download)
ARG RESTIC_REPO=https://github.com/restic/restic.git
ARG RESTIC_ARCHIVE=https://github.com/restic/restic/archive/refs/heads/master.zip
ARG RCLONE_REPO=https://github.com/rclone/rclone.git
ARG RCLONE_ARCHIVE=https://github.com/rclone/rclone/archive/refs/heads/master.zip

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    zip \
    bzip2 \
    && rm -rf /var/lib/apt/lists/*

# Download and install patched Go SDK
WORKDIR /opt
RUN curl -fsSL "https://github.com/XTLS/go-win7/releases/download/${GO_WIN7_TAG}/go-for-win7-linux-amd64.zip" \
    -o go-win7.zip \
    && unzip -q go-win7.zip -d go-win7 \
    && rm go-win7.zip \
    && chmod +x /opt/go-win7/bin/*

# Configure Go environment variables
ENV GOROOT=/opt/go-win7
ENV PATH="${GOROOT}/bin:${PATH}"
ENV GO111MODULE=on
ENV CGO_ENABLED=0

# URLs for auto-download (available in build script)
ENV RESTIC_GIT_URL=${RESTIC_REPO}
ENV RESTIC_ARCHIVE_URL=${RESTIC_ARCHIVE}
ENV RCLONE_GIT_URL=${RCLONE_REPO}
ENV RCLONE_ARCHIVE_URL=${RCLONE_ARCHIVE}

# Go cache - mount a volume here to speed up subsequent builds
ENV GOPATH=/go
ENV GOCACHE=/go/cache
# Disable VCS stamping (avoids permission errors with .git directory)
ENV GOFLAGS="-buildvcs=false"

# Working directory (mounted by user)
WORKDIR /workspace

# Create directories for Go cache
RUN mkdir -p /go/cache /go/pkg

# Build script
COPY build.sh /usr/local/bin/build.sh
RUN chmod +x /usr/local/bin/build.sh

# Volume for build results
VOLUME ["/workspace"]

# Default: build for both Windows architectures
ENTRYPOINT ["/usr/local/bin/build.sh"]
CMD ["all"]
