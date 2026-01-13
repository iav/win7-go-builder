#!/bin/bash
# =============================================================================
# Build script for restic and rclone with Windows 7 support
# =============================================================================
# Standalone script: automatically finds or downloads source code.
#
# Supported projects:
#   - restic: backup program (uses build.go for compilation)
#   - rclone: cloud storage sync tool (uses standard go build)
#
# Command format:
#   project:arch    e.g., restic:amd64, rclone:all
#   arch            e.g., amd64, 386, all (defaults to restic)
#
# Version selection:
#   RESTIC_VERSION=v0.17.3  - specific tag/branch/commit
#   RCLONE_VERSION=v1.68.2  - specific tag/branch/commit
#   If not set, fetches latest release tag from GitHub API
#
# Source detection logic:
#   1. Checks workspace (/workspace) for go.mod with project module
#   2. Searches subdirectories (restic/, rclone/, etc.)
#   3. If not found — attempts to clone from GitHub with specified version
#   4. If git clone fails — attempts to download archive
#   5. If all fails — shows instructions
# =============================================================================
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()  { echo -e "${BLUE}[====]${NC} $1" >&2; }

# Configuration
WORKSPACE="${WORKSPACE:-/workspace}"
OUTPUT_DIR="${WORKSPACE}/output"

# restic configuration
RESTIC_GIT_URL="${RESTIC_GIT_URL:-https://github.com/restic/restic.git}"
RESTIC_REPO_API="${RESTIC_REPO_API:-https://api.github.com/repos/restic/restic}"

# rclone configuration
RCLONE_GIT_URL="${RCLONE_GIT_URL:-https://github.com/rclone/rclone.git}"
RCLONE_REPO_API="${RCLONE_REPO_API:-https://api.github.com/repos/rclone/rclone}"

# Version configuration (can be tag, branch, or commit hash)
# If empty, will fetch latest release tag from GitHub
RESTIC_VERSION="${RESTIC_VERSION:-}"
RCLONE_VERSION="${RCLONE_VERSION:-}"

# Resolved versions (set during runtime)
declare -A RESOLVED_VERSIONS

# =============================================================================
# Version management functions
# =============================================================================

# Sanitize version string for use in filename (replace : with _)
sanitize_version() {
    local version="$1"
    echo "${version}" | sed 's/:/_/g; s/[^a-zA-Z0-9._-]/_/g'
}

# Get latest release tag from GitHub API
get_latest_tag() {
    local project="$1"
    local api_url_var="${project^^}_REPO_API"
    local api_url="${!api_url_var}"

    log_info "Fetching latest ${project} release tag from GitHub..."

    local latest_tag
    latest_tag=$(curl -fsSL "${api_url}/releases/latest" 2>/dev/null | \
                 grep -oP '"tag_name"\s*:\s*"\K[^"]+' || echo "")

    if [ -z "${latest_tag}" ]; then
        # Fallback: try to get latest tag from tags API
        latest_tag=$(curl -fsSL "${api_url}/tags" 2>/dev/null | \
                     grep -oP '"name"\s*:\s*"\K[^"]+' | head -1 || echo "")
    fi

    if [ -z "${latest_tag}" ]; then
        log_warn "Could not fetch latest tag for ${project}, using 'master'"
        echo "master"
    else
        log_info "Latest ${project} release: ${latest_tag}"
        echo "${latest_tag}"
    fi
}

# Resolve version for a project (use specified or fetch latest)
resolve_version() {
    local project="$1"
    local version_var="${project^^}_VERSION"
    local version="${!version_var}"

    if [ -n "${version}" ]; then
        log_info "Using specified ${project} version: ${version}"
        RESOLVED_VERSIONS[${project}]="${version}"
    else
        RESOLVED_VERSIONS[${project}]=$(get_latest_tag "${project}")
    fi
}

# Get resolved version for a project
get_resolved_version() {
    local project="$1"
    echo "${RESOLVED_VERSIONS[${project}]:-master}"
}

# =============================================================================
# Source detection functions
# =============================================================================

is_restic_source() {
    local dir="$1"
    if [ -f "${dir}/go.mod" ]; then
        if grep -q 'module github.com/restic/restic' "${dir}/go.mod" 2>/dev/null; then
            return 0
        fi
    fi
    if [ -f "${dir}/VERSION" ] && [ -d "${dir}/cmd/restic" ]; then
        return 0
    fi
    return 1
}

is_rclone_source() {
    local dir="$1"
    if [ -f "${dir}/go.mod" ]; then
        if grep -q 'module github.com/rclone/rclone' "${dir}/go.mod" 2>/dev/null; then
            return 0
        fi
    fi
    if [ -f "${dir}/VERSION" ] && [ -d "${dir}/cmd/rclone" ]; then
        return 0
    fi
    return 1
}

find_project_source() {
    local project="$1"
    local is_source_func="is_${project}_source"

    log_step "Searching for ${project} source..."

    # 1. Check workspace root
    if ${is_source_func} "${WORKSPACE}"; then
        log_info "Source found in: ${WORKSPACE}"
        echo "${WORKSPACE}"
        return 0
    fi

    # 2. Check common subdirectory names
    local search_dirs=(
        "${project}"
        "${project}-master"
        "${project}-main"
        "src"
        "source"
    )

    for subdir in "${search_dirs[@]}"; do
        local path="${WORKSPACE}/${subdir}"
        if [ -d "${path}" ] && ${is_source_func} "${path}"; then
            log_info "Source found in: ${path}"
            echo "${path}"
            return 0
        fi
    done

    # 3. Search all first-level subdirectories
    for dir in "${WORKSPACE}"/*/; do
        if [ -d "${dir}" ] && ${is_source_func} "${dir}"; then
            log_info "Source found in: ${dir}"
            echo "${dir%/}"
            return 0
        fi
    done

    return 1
}

download_project_source() {
    local project="$1"
    local git_url_var="${project^^}_GIT_URL"
    local git_url="${!git_url_var}"
    local target_dir="${WORKSPACE}/${project}"
    local is_source_func="is_${project}_source"
    local version=$(get_resolved_version "${project}")

    log_step "Source not found. Downloading ${project} (${version})..."

    # Remove existing target directory if present
    rm -rf "${target_dir}"

    # Attempt: git clone with specific version
    log_info "Attempting: git clone ${git_url} (${version})"

    # First clone, then checkout specific version
    if git clone "${git_url}" "${target_dir}" 2>/dev/null; then
        cd "${target_dir}"
        if git checkout "${version}" 2>/dev/null; then
            log_info "Successfully cloned ${project} at ${version}"
            echo "${target_dir}"
            return 0
        else
            log_warn "Could not checkout ${version}, using default branch"
            echo "${target_dir}"
            return 0
        fi
    fi

    log_warn "git clone failed"

    # Fallback: try archive download for tags
    if [[ "${version}" == v* ]]; then
        local archive_url="https://github.com/${project}/${project}/archive/refs/tags/${version}.zip"
        log_info "Attempting: download archive ${archive_url}"
        local archive_file="${WORKSPACE}/${project}-${version}.zip"

        if curl -fsSL "${archive_url}" -o "${archive_file}" 2>/dev/null; then
            log_info "Archive downloaded, extracting..."

            if unzip -q "${archive_file}" -d "${WORKSPACE}" 2>/dev/null; then
                rm -f "${archive_file}"

                # Find extracted directory (usually project-version without 'v')
                local version_no_v="${version#v}"
                for dir in "${WORKSPACE}/${project}-${version_no_v}" "${WORKSPACE}/${project}-${version}" "${WORKSPACE}"/${project}-*/; do
                    if [ -d "${dir}" ] && ${is_source_func} "${dir}"; then
                        # Rename to standard name
                        if [ "${dir}" != "${target_dir}" ]; then
                            mv "${dir}" "${target_dir}"
                        fi
                        log_info "Successfully extracted to ${target_dir}"
                        echo "${target_dir}"
                        return 0
                    fi
                done
            fi
            rm -f "${archive_file}"
        fi
    fi

    log_warn "Download failed"
    return 1
}

get_project_source() {
    local project="$1"
    find_project_source "${project}" || download_project_source "${project}"
}

# Checkout specific version in existing source directory
checkout_version() {
    local project="$1"
    local src_dir="$2"
    local version=$(get_resolved_version "${project}")

    if [ -d "${src_dir}/.git" ]; then
        log_info "Checking out ${project} version: ${version}"
        cd "${src_dir}"

        # Fetch all tags and branches
        git fetch --all --tags 2>/dev/null || true

        # Try to checkout the version
        if git checkout "${version}" 2>/dev/null; then
            log_info "Checked out ${version}"
        else
            log_warn "Could not checkout ${version}, using current state"
        fi
    fi
}

# =============================================================================
# Build functions
# =============================================================================

build_restic() {
    local src_dir="$1"
    local goos="$2"
    local goarch="$3"
    local output_name="$4"

    log_info "Building restic for ${goos}/${goarch}..."

    cd "${src_dir}"

    # restic uses build.go with custom flags
    # Don't set GOOS/GOARCH here - build.go handles them via arguments
    # -buildvcs=false disables VCS stamping (avoids .git permission errors)
    go run -buildvcs=false build.go \
        --goos "${goos}" \
        --goarch "${goarch}" \
        -o "${OUTPUT_DIR}/${output_name}"

    verify_build "${output_name}"
}

build_rclone() {
    local src_dir="$1"
    local goos="$2"
    local goarch="$3"
    local output_name="$4"

    log_info "Building rclone for ${goos}/${goarch}..."

    cd "${src_dir}"

    # Get version info for ldflags
    local version=$(cat VERSION 2>/dev/null || echo "unknown")
    local git_tag=$(git describe --tags 2>/dev/null || echo "")

    # rclone uses standard go build
    CGO_ENABLED=0 GOOS="${goos}" GOARCH="${goarch}" \
        go build -buildvcs=false \
        -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=${version}" \
        -o "${OUTPUT_DIR}/${output_name}" \
        .

    verify_build "${output_name}"
}

verify_build() {
    local output_name="$1"

    if [ -f "${OUTPUT_DIR}/${output_name}" ]; then
        local size=$(du -h "${OUTPUT_DIR}/${output_name}" | cut -f1)
        local file_info=$(file "${OUTPUT_DIR}/${output_name}" 2>/dev/null | grep -o 'MS Windows [0-9.]*' || echo "")
        if [ -n "${file_info}" ]; then
            log_info "Done: ${output_name} (${size}, ${file_info})"
        else
            log_info "Done: ${output_name} (${size})"
        fi
    else
        log_error "Build failed: ${output_name}"
        return 1
    fi
}

# =============================================================================
# Build orchestration
# =============================================================================

build_project_arch() {
    local project="$1"
    local arch="$2"
    local src_dir="$3"

    local build_func="build_${project}"
    local version=$(get_resolved_version "${project}")
    local safe_version=$(sanitize_version "${version}")

    # Naming convention: project-VERSION-win7-64.exe / project-VERSION-win7-32.exe
    # Following XTLS/Xray-core pattern for Windows 7 legacy builds
    case "${arch}" in
        amd64|x64|64)
            ${build_func} "${src_dir}" windows amd64 "${project}-${safe_version}-win7-64.exe"
            ;;
        386|x86|32)
            ${build_func} "${src_dir}" windows 386 "${project}-${safe_version}-win7-32.exe"
            ;;
        all)
            ${build_func} "${src_dir}" windows amd64 "${project}-${safe_version}-win7-64.exe"
            ${build_func} "${src_dir}" windows 386 "${project}-${safe_version}-win7-32.exe"
            ;;
        linux)
            ${build_func} "${src_dir}" linux amd64 "${project}-${safe_version}-linux-amd64"
            ;;
        *)
            log_error "Unknown architecture: ${arch}"
            return 1
            ;;
    esac
}

# =============================================================================
# Command parsing
# =============================================================================

parse_and_build() {
    local command="$1"

    # Check for composite command (project:arch)
    if [[ "${command}" == *":"* ]]; then
        local project="${command%%:*}"
        local arch="${command##*:}"

        if [ "${project}" = "all" ]; then
            # Build all projects
            build_single_project "restic" "${arch}"
            build_single_project "rclone" "${arch}"
        else
            build_single_project "${project}" "${arch}"
        fi
    else
        # Legacy mode: just architecture, default to restic
        build_single_project "restic" "${command}"
    fi
}

build_single_project() {
    local project="$1"
    local arch="$2"

    case "${project}" in
        restic|rclone)
            log_step "Building ${project}..."

            # Resolve version if not already done
            if [ -z "${RESOLVED_VERSIONS[${project}]}" ]; then
                resolve_version "${project}"
            fi

            local src_dir
            src_dir=$(get_project_source "${project}") || {
                show_manual_instructions "${project}"
                return 1
            }

            # Checkout specific version if source was found (not downloaded)
            checkout_version "${project}" "${src_dir}"

            # Show version info
            show_version_info "${project}" "${src_dir}"

            # Build
            build_project_arch "${project}" "${arch}" "${src_dir}"
            ;;
        *)
            log_error "Unknown project: ${project}"
            log_error "Supported projects: restic, rclone"
            return 1
            ;;
    esac
}

show_version_info() {
    local project="$1"
    local src_dir="$2"

    local version=$(cat "${src_dir}/VERSION" 2>/dev/null || echo "unknown")
    local git_version=$(cd "${src_dir}" && git describe --long --tags --dirty --always 2>/dev/null || echo "")
    local requested_version=$(get_resolved_version "${project}")

    if [ -n "${git_version}" ]; then
        log_info "${project} version: ${version} (${git_version}) [requested: ${requested_version}]"
    else
        log_info "${project} version: ${version} [requested: ${requested_version}]"
    fi
}

# =============================================================================
# Help and instructions
# =============================================================================

show_help() {
    echo "Build restic and rclone for Windows 7"
    echo ""
    echo "Usage: $0 [COMMAND]..."
    echo ""
    echo "Commands (new format - project:arch):"
    echo "  restic:all      Build restic for Windows 64-bit and 32-bit"
    echo "  restic:amd64    Build restic for Windows 64-bit only"
    echo "  restic:386      Build restic for Windows 32-bit only"
    echo "  rclone:all      Build rclone for Windows 64-bit and 32-bit"
    echo "  rclone:amd64    Build rclone for Windows 64-bit only"
    echo "  rclone:386      Build rclone for Windows 32-bit only"
    echo "  all:all         Build everything (restic + rclone, both architectures)"
    echo "  all:amd64       Build everything for 64-bit only"
    echo ""
    echo "Commands (legacy format - restic only):"
    echo "  all             Build restic for Windows 64-bit and 32-bit (default)"
    echo "  amd64           Build restic for Windows 64-bit only"
    echo "  386             Build restic for Windows 32-bit only"
    echo "  linux           Build restic for Linux 64-bit"
    echo ""
    echo "Multiple commands can be specified:"
    echo "  $0 restic:amd64 rclone:amd64"
    echo ""
    echo "The script automatically:"
    echo "  1. Searches for source code in /workspace"
    echo "  2. If not found — downloads from GitHub"
    echo "  3. Builds binaries to /workspace/output/"
    echo ""
    echo "Environment variables:"
    echo "  WORKSPACE            Working directory (default: /workspace)"
    echo "  RESTIC_VERSION       restic version/tag/commit (default: latest release)"
    echo "  RCLONE_VERSION       rclone version/tag/commit (default: latest release)"
    echo "  RESTIC_GIT_URL       Git URL for restic"
    echo "  RCLONE_GIT_URL       Git URL for rclone"
    echo ""
    echo "Examples:"
    echo "  # Build latest versions"
    echo "  $0 all:all"
    echo ""
    echo "  # Build specific versions"
    echo "  RESTIC_VERSION=v0.17.3 RCLONE_VERSION=v1.68.2 $0 all:all"
    echo ""
    echo "  # Build from specific commit"
    echo "  RESTIC_VERSION=abc1234 $0 restic:amd64"
    echo ""
    echo "Output files: project-VERSION-win7-64.exe, project-VERSION-win7-32.exe"
    echo ""
}

show_manual_instructions() {
    local project="$1"
    local git_url_var="${project^^}_GIT_URL"
    local git_url="${!git_url_var}"
    local version=$(get_resolved_version "${project}")

    echo ""
    log_error "=========================================="
    log_error "  FAILED TO FIND OR DOWNLOAD SOURCE"
    log_error "=========================================="
    echo ""
    echo -e "${project} source not found in workspace."
    echo -e "Attempted to download version: ${version}"
    echo -e "From: ${git_url}"
    echo ""
    echo -e "${YELLOW}Get the source manually:${NC}"
    echo ""
    echo -e "  ${GREEN}Option 1: git clone${NC}"
    echo -e "    git clone --branch ${version} ${git_url}"
    echo ""
    echo -e "  ${GREEN}Option 2: download archive${NC}"
    echo -e "    Visit https://github.com/${project}/${project}/releases"
    echo -e "    Download the source archive for ${version}"
    echo ""
    echo -e "Then run the container with mounted source directory:"
    echo ""
    echo -e "  docker run --rm -v /path/to/source:/workspace win7-builder ${project}:all"
    echo ""
}

# =============================================================================
# Main logic
# =============================================================================

main() {
    # Handle help
    if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
        exit 0
    fi

    echo ""
    log_step "Windows 7 Builder (restic + rclone)"
    log_info "Go version: $(go version | grep -oP 'go[0-9.]+')"
    log_info "Workspace: ${WORKSPACE}"

    # Show configured versions
    if [ -n "${RESTIC_VERSION}" ]; then
        log_info "RESTIC_VERSION: ${RESTIC_VERSION}"
    fi
    if [ -n "${RCLONE_VERSION}" ]; then
        log_info "RCLONE_VERSION: ${RCLONE_VERSION}"
    fi
    echo ""

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"

    # Process commands
    local commands=("$@")
    if [ "${#commands[@]}" -eq 0 ]; then
        commands=("all")  # Default: restic all
    fi

    for cmd in "${commands[@]}"; do
        parse_and_build "${cmd}"
    done

    echo ""
    log_step "Build completed!"
    log_info "Results in: ${OUTPUT_DIR}/"
    echo ""
    ls -lah "${OUTPUT_DIR}/"* 2>/dev/null || true
    echo ""
}

main "$@"
