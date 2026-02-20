#!/bin/bash

# Simple script to verify local Docker image builds
# Builds base and final images locally for testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
PHP_VERSION=""
VARIANT=""
BUILD_MODE=""
GITHUB_TOKEN=""
DOCKER_BUILD_OPTS=""
OS=""
OS_SET=0

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -v, --version VERSION       PHP version (e.g., 8.4.15, 8.3.28)
    -t, --variant VARIANT       Variant type (cli, cli-alpine, zts, zts-alpine, apache, fpm, fpm-alpine)
    -s, --os OS                 Base builder OS (debian or alpine). If omitted, derived from VARIANT ("-alpine" suffix means alpine)
    -m, --mode MODE             Build mode: 'base' for prebuild images, 'final' for final images, 'both' for both
    -g, --github-token TOKEN    GitHub token (optional, will try to retrieve from composer if not provided)
    -o, --docker-opts OPTS      Extra options passed to 'docker buildx build' (e.g. \`--no-cache --progress=plain\`)
    -h, --help                  Display this help message

Examples:
    # Build base image only (prebuild)
    $0 --version 8.4.15 --variant cli --mode base

    # Build final image using existing prebuild
    $0 --version 8.4.15 --variant cli --mode final

    # Build both base and final images
    $0 --version 8.4.15 --variant cli --mode both

    # Build with custom GitHub token and extra docker build options
    $0 --version 8.4.15 --variant cli --mode both --github-token ghp_xxxxx --docker-opts "--no-cache --progress=plain"

EOF
    exit 1
}

# Function to retrieve GitHub token from composer
get_github_token_from_composer() {
    echo -e "${YELLOW}Attempting to retrieve GitHub token from Composer...${NC}" >&2

    # Try to get token from composer config
    local token=$(composer config --global github-oauth.github.com 2>/dev/null || echo "")

    if [ -n "$token" ]; then
        echo -e "${GREEN}GitHub token retrieved from Composer configuration${NC}" >&2
        echo "$token"
    else
        echo -e "${YELLOW}No GitHub token found in Composer configuration${NC}" >&2
        echo ""
    fi
}

# Function to validate variant
validate_variant() {
    local variant=$1
    local valid_variants=("cli" "cli-alpine" "zts" "zts-alpine" "apache" "fpm" "fpm-alpine")

    for valid in "${valid_variants[@]}"; do
        if [ "$variant" = "$valid" ]; then
            return 0
        fi
    done

    echo -e "${RED}Error: Invalid variant '$variant'${NC}"
    echo "Valid variants: ${valid_variants[*]}"
    exit 1
}

# Helper: split a variant into name and os
# Outputs: <name> <os> (os is 'debian' or 'alpine')
get_variant_parts() {
    local variant=$1
    if [[ "$variant" == *"-alpine" ]]; then
        echo "${variant%-alpine} alpine"
    else
        echo "$variant debian"
    fi
}

# Helper: map final variant name to base variant name (cli/zts)
get_base_name() {
    local name=$1
    case "$name" in
        apache|fpm)
            echo "cli"
            ;;
        *)
            echo "$name"
            ;;
    esac
}

# Function to check if variant needs base build (base variants are cli and zts)
needs_base_build() {
    local variant=$1
    case "$variant" in
        cli|cli-alpine|zts|zts-alpine)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to build base (prebuild) image
# Arguments: version, base_name, os, github_token
build_base_image() {
    local version=$1
    local base_name=$2
    local os=$3
    local github_token=$4

    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Building BASE image for PHP ${version} ${base_name} (os: ${os})${NC}"
    echo -e "${GREEN}======================================${NC}"

    local dockerfile="builder/${os}/Dockerfile"
    local tag_variant="$base_name"
    if [ "$os" != "debian" ]; then
        tag_variant="${tag_variant}-${os}"
    fi
    local image_tag="php:${version}-${tag_variant}-prebuild"

    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}Error: Dockerfile not found: $dockerfile${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Building: $image_tag${NC}"

    # Split DOCKER_BUILD_OPTS into an array (safe splitting)
    read -r -a DOCKER_BUILD_OPTS_ARR <<< "$DOCKER_BUILD_OPTS"

    if [ -n "$github_token" ]; then
        echo -e "${YELLOW}Using provided GitHub token${NC}"
        echo "$github_token" | docker buildx build "${DOCKER_BUILD_OPTS_ARR[@]}" \
            --pull \
            --file "$dockerfile" \
            --build-arg PHP_VERSION="$version" \
            --build-arg PHP_VARIANT="$base_name" \
            --tag "$image_tag" \
            --secret id=github_token,src=/dev/stdin \
            .
    else
        echo -e "${YELLOW}Warning: No GitHub token provided. Build may fail if private repositories are accessed.${NC}"
        docker buildx build "${DOCKER_BUILD_OPTS_ARR[@]}" \
            --pull \
            --file "$dockerfile" \
            --build-arg PHP_VERSION="$version" \
            --build-arg PHP_VARIANT="$base_name" \
            --tag "$image_tag" \
            .
    fi

    echo -e "${GREEN}Base image built successfully: $image_tag${NC}"
}

# Function to build final image
build_final_image() {
    local version=$1
    local variant=$2
    local resolved_os=$3

    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Building FINAL image for PHP ${version} ${variant}${NC}"
    echo -e "${GREEN}======================================${NC}"

    local dockerfile="Dockerfile-${variant}"
    local image_tag="php:${version}-${variant}"

    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}Error: Dockerfile not found: $dockerfile${NC}"
        exit 1
    fi

    # Determine base variant name and use resolved OS (priority: function arg, else derive from variant)
    read -r name derived_os <<< "$(get_variant_parts "$variant")"
    base_name=$(get_base_name "$name")
    os="${resolved_os:-$derived_os}"
    base_tag_variant="$base_name"
    if [ "$os" != "debian" ]; then
        base_tag_variant="${base_tag_variant}-${os}"
    fi

    # Check if required prebuild image exists locally
    local prebuild_image="php:${version}-${base_tag_variant}-prebuild"
    if ! docker image inspect "$prebuild_image" >/dev/null 2>&1; then
        echo -e "${RED}Error: Required prebuild image not found: ${prebuild_image}${NC}"
        echo "Tip: Build it first with:"
        echo "  $0 --version $version --variant ${base_name}$( [ "$os" != "debian" ] && echo "-${os}" ) --mode base"
        echo "Or use:"
        echo "  $0 --version $version --variant $variant --mode both"
        exit 1
    fi

    local build_contexts=""

    # Only add the specific build context needed for this variant
    build_contexts="--build-context php-${version}-${base_tag_variant}=docker-image://php:${version}-${base_tag_variant}-prebuild"

    echo -e "${YELLOW}Building: $image_tag${NC}"
    echo -e "${YELLOW}Using base context: php-${version}-${base_tag_variant}-prebuild${NC}"

    # Pre-pull official base image to ensure it's up-to-date
    echo -e "${YELLOW}Ensuring official base image is up-to-date: php:${version}-${variant}${NC}"
    docker pull "php:${version}-${variant}" >/dev/null || true

    # Split DOCKER_BUILD_OPTS into an array (safe splitting)
    read -r -a DOCKER_BUILD_OPTS_ARR <<< "$DOCKER_BUILD_OPTS"

    docker buildx build "${DOCKER_BUILD_OPTS_ARR[@]}" \
        --file "$dockerfile" \
        --build-arg PHP_VERSION="$version" \
        $build_contexts \
        --tag "$image_tag" \
        .

    echo -e "${GREEN}Final image built successfully: $image_tag${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            PHP_VERSION="$2"
            shift 2
            ;;
        -t|--variant)
            VARIANT="$2"
            shift 2
            ;;
        -s|--os)
            OS="$2"
            OS_SET=1
            shift 2
            ;;
        -m|--mode)
            BUILD_MODE="$2"
            shift 2
            ;;
        -g|--github-token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        -o|--docker-opts)
            DOCKER_BUILD_OPTS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$PHP_VERSION" ]; then
    echo -e "${RED}Error: PHP version is required${NC}"
    usage
fi

if [ -z "$VARIANT" ]; then
    echo -e "${RED}Error: Variant is required${NC}"
    usage
fi

if [ -z "$BUILD_MODE" ]; then
    echo -e "${RED}Error: Build mode is required${NC}"
    usage
fi

# Validate variant
validate_variant "$VARIANT"

# Validate build mode
if [[ ! "$BUILD_MODE" =~ ^(base|final|both)$ ]]; then
    echo -e "${RED}Error: Invalid build mode '$BUILD_MODE'. Must be 'base', 'final', or 'both'${NC}"
    exit 1
fi

if [ "$OS_SET" -eq 1 ]; then
    # user provided OS: normalize input and validate
    if [ "$OS" != "debian" ] && [ "$OS" != "alpine" ]; then
        echo -e "${RED}Error: Invalid OS '$OS'. Must be 'debian' or 'alpine'${NC}"
        exit 1
    fi
else
    # derive from variant (variants with -alpine map to alpine, otherwise debian)
    read -r _derived_name _derived_os <<< "$(get_variant_parts "$VARIANT")"
    OS="${_derived_os:-debian}"
fi

# Get GitHub token from composer if not provided
if [ -z "$GITHUB_TOKEN" ]; then
    GITHUB_TOKEN=$(get_github_token_from_composer)
fi

# Display configuration
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Build Configuration${NC}"
echo -e "${GREEN}======================================${NC}"
echo "PHP Version:       $PHP_VERSION"
echo "Variant:           $VARIANT"
echo "OS:                $OS"
echo "Build Mode:        $BUILD_MODE"
echo "GitHub Token:      $([ -n "$GITHUB_TOKEN" ] && echo "Provided" || echo "Not provided")"
echo "Docker build opts:  $([ -n "$DOCKER_BUILD_OPTS" ] && echo "$DOCKER_BUILD_OPTS" || echo "None")"
echo -e "${GREEN}======================================${NC}"
echo ""

# Ensure docker is available
if ! docker version >/dev/null 2>&1; then
    echo -e "${RED}Error: docker is not available${NC}"
    exit 1
fi

# Execute build based on mode
case "$BUILD_MODE" in
    base)
        # For base, we need the base variant name and the OS
        read -r name name_os <<< "$(get_variant_parts "$VARIANT")"
        # If user provided an explicit OS, prefer that
        if [ -n "$OS" ]; then
            name_os="$OS"
        fi
        base_name=$(get_base_name "$name")
        if needs_base_build "$base_name"; then
            build_base_image "$PHP_VERSION" "$base_name" "$name_os" "$GITHUB_TOKEN"
        else
            echo -e "${RED}Error: Variant '$VARIANT' does not have a base build${NC}"
            exit 1
        fi
        ;;
    final)
        build_final_image "$PHP_VERSION" "$VARIANT" "$OS"
        ;;
    both)
        # Determine whether the variant itself requires a base build, otherwise build the appropriate base
        if needs_base_build "$VARIANT"; then
            # variant is something like cli or cli-alpine / zts etc.
            read -r name name_os <<< "$(get_variant_parts "$VARIANT")"
            if [ -n "$OS" ]; then
                name_os="$OS"
            fi
            build_base_image "$PHP_VERSION" "$name" "$name_os" "$GITHUB_TOKEN"
        else
            # For variants without their own base build, we need the appropriate base variant and same OS
            read -r name name_os <<< "$(get_variant_parts "$VARIANT")"
            if [ -n "$OS" ]; then
                name_os="$OS"
            fi
            base_name=$(get_base_name "$name")
            echo -e "${YELLOW}Variant '$VARIANT' uses base variant '${base_name}' (os: ${name_os})${NC}"
            echo -e "${YELLOW}Building required prebuild image for '${base_name}'${NC}"
            echo ""
            build_base_image "$PHP_VERSION" "$base_name" "$name_os" "$GITHUB_TOKEN"
        fi
        build_final_image "$PHP_VERSION" "$VARIANT" "$OS"
        ;;
esac

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Build completed successfully!${NC}"
echo -e "${GREEN}======================================${NC}"
