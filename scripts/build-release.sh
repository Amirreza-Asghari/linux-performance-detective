#!/usr/bin/env bash

set -u
set -o pipefail


SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

PROJECT_ROOT="$(
    cd -- "$SCRIPT_DIR/.." &&
    pwd
)"


source "$PROJECT_ROOT/lib/common.sh"


DIST_DIR="$PROJECT_ROOT/dist"

PACKAGE_NAME="linux-performance-detective-$LPD_VERSION"

ARCHIVE="$DIST_DIR/$PACKAGE_NAME.tar.gz"
CHECKSUM="$ARCHIVE.sha256"


BUILD_ROOT=""


cleanup_build() {

    if [[ -n "$BUILD_ROOT" &&
          -d "$BUILD_ROOT" ]]; then

        rm -rf -- "$BUILD_ROOT"
    fi
}


trap cleanup_build EXIT


fail_build() {

    printf "[BUILD ERROR] %s\n" "$1" >&2

    exit 1
}


build_info() {

    printf "[BUILD] %s\n" "$1"
}


#
# ------------------------------------------------------------
# REQUIRED BUILD TOOLS
# ------------------------------------------------------------
#

for tool in \
    tar \
    gzip \
    sha256sum \
    mktemp \
    cp \
    find \
    sort
do

    command -v "$tool" \
        >/dev/null \
        2>&1 \
        || fail_build "Required build tool missing: $tool"

done


#
# ------------------------------------------------------------
# VERSION
# ------------------------------------------------------------
#

[[ -n "${LPD_VERSION:-}" ]] ||
    fail_build "LPD_VERSION is empty"


if [[ ! "$LPD_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?$ ]]; then

    fail_build "Invalid version string: $LPD_VERSION"
fi


build_info "Version: $LPD_VERSION"


#
# ------------------------------------------------------------
# REQUIRED PROJECT PATHS
# ------------------------------------------------------------
#

required_paths=(

    lpd.sh
    lib
    checks
    diagnostics
    fixes
    verify
    config
    tests
)


for path in "${required_paths[@]}"; do

    if [[ ! -e "$PROJECT_ROOT/$path" ]]; then

        fail_build "Required project path missing: $path"
    fi

done


#
# ------------------------------------------------------------
# CREATE ISOLATED STAGING TREE
# ------------------------------------------------------------
#

mkdir -p "$DIST_DIR" ||
    fail_build "Unable to create dist directory"


BUILD_ROOT="$(
    mktemp -d /tmp/lpd-release-build.XXXXXX
)" || fail_build "Unable to create temporary build directory"


PACKAGE_ROOT="$BUILD_ROOT/$PACKAGE_NAME"


mkdir -p "$PACKAGE_ROOT" ||
    fail_build "Unable to create staging directory"


build_info "Preparing isolated staging tree"


#
# ------------------------------------------------------------
# COPY PRODUCT
# ------------------------------------------------------------
#

for path in "${required_paths[@]}"; do

    cp -a \
        "$PROJECT_ROOT/$path" \
        "$PACKAGE_ROOT/" \
        || fail_build "Unable to copy $path"

done


#
# ------------------------------------------------------------
# OPTIONAL PROJECT CONTENT
# ------------------------------------------------------------
#
# These paths are included when they exist.
# Packaging does not require documentation to exist yet.
#

optional_paths=(

    README.md
    LICENSE
    CHANGELOG.md
    docs
    incidents
    baseline
)


for path in "${optional_paths[@]}"; do

    if [[ -e "$PROJECT_ROOT/$path" ]]; then

        cp -a \
            "$PROJECT_ROOT/$path" \
            "$PACKAGE_ROOT/" \
            || fail_build "Unable to copy optional path: $path"

    fi

done


#
# ------------------------------------------------------------
# EMPTY RUNTIME DIRECTORIES
# ------------------------------------------------------------
#
# Existing logs/reports/evidence from the development system
# are intentionally NOT copied.
#

mkdir -p \
    "$PACKAGE_ROOT/logs" \
    "$PACKAGE_ROOT/reports" \
    "$PACKAGE_ROOT/evidence" \
    || fail_build "Unable to create runtime directories"


#
# ------------------------------------------------------------
# REMOVE DEVELOPMENT ARTIFACTS
# ------------------------------------------------------------
#

find "$PACKAGE_ROOT" \
    -type d \
    -name '__pycache__' \
    -prune \
    -exec rm -rf -- {} +


find "$PACKAGE_ROOT" \
    -type f \
    \( \
        -name '*.pyc' \
        -o -name '*.pyo' \
        -o -name '*.swp' \
        -o -name '*.swo' \
        -o -name '*~' \
        -o -name '.DS_Store' \
    \) \
    -delete


#
# ------------------------------------------------------------
# EXECUTABLE PERMISSIONS
# ------------------------------------------------------------
#

chmod +x "$PACKAGE_ROOT/lpd.sh" ||
    fail_build "Unable to set lpd.sh executable permission"


if [[ -d "$PACKAGE_ROOT/tests" ]]; then

    find "$PACKAGE_ROOT/tests" \
        -type f \
        -name '*.sh' \
        -exec chmod +x {} +

fi


#
# ------------------------------------------------------------
# PACKAGE MANIFEST
# ------------------------------------------------------------
#

MANIFEST="$PACKAGE_ROOT/PACKAGE-MANIFEST.txt"


{
    printf "Linux Performance Detective\n"
    printf "Version: %s\n" "$LPD_VERSION"
    printf "Package: %s\n" "$PACKAGE_NAME"

    echo
    echo "Files:"

    cd "$PACKAGE_ROOT" || exit 1

    find . \
        -type f \
        -printf '%P\n' |
        LC_ALL=C sort

} > "$MANIFEST" || fail_build "Unable to create package manifest"


#
# ------------------------------------------------------------
# PRE-ARCHIVE VALIDATION
# ------------------------------------------------------------
#

build_info "Validating staged package"


bash -n "$PACKAGE_ROOT/lpd.sh" ||
    fail_build "Packaged lpd.sh failed Bash syntax validation"


if [[ ! -f "$PACKAGE_ROOT/config/lpd.conf" ]]; then

    fail_build "Packaged configuration is missing"
fi


for directory in \
    logs \
    reports \
    evidence
do

    if find "$PACKAGE_ROOT/$directory" \
        -mindepth 1 \
        -print \
        -quit |
        grep -q .
    then

        fail_build "Runtime directory is not empty: $directory"
    fi

done


#
# ------------------------------------------------------------
# BUILD REPRODUCIBLE ARCHIVE
# ------------------------------------------------------------
#
# Stable ordering, owner metadata and gzip timestamp make the
# same source tree produce a stable archive.
#

rm -f \
    "$ARCHIVE" \
    "$CHECKSUM"


build_info "Creating archive"


tar \
    --sort=name \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --mtime='UTC 1970-01-01' \
    -C "$BUILD_ROOT" \
    -cf - \
    "$PACKAGE_NAME" |
gzip -n \
    > "$ARCHIVE" \
    || fail_build "Unable to create release archive"


#
# ------------------------------------------------------------
# CHECKSUM
# ------------------------------------------------------------
#

(
    cd "$DIST_DIR" || exit 1

    sha256sum \
        "$(basename "$ARCHIVE")" \
        > "$(basename "$CHECKSUM")"

) || fail_build "Unable to create SHA256 checksum"


#
# ------------------------------------------------------------
# ARCHIVE CONTENT SAFETY
# ------------------------------------------------------------
#

build_info "Checking archive contents"


if tar -tzf "$ARCHIVE" |
   grep -E '(^|/)\.\.(/|$)' \
   >/dev/null
then

    fail_build "Unsafe parent traversal path found in archive"
fi


if tar -tzf "$ARCHIVE" |
   grep -E '^/' \
   >/dev/null
then

    fail_build "Absolute path found in archive"
fi


#
# Runtime directories may exist, but they must be empty.
#

for directory in \
    logs \
    reports \
    evidence
do

    if tar -tzf "$ARCHIVE" |
       grep -E \
           "^${PACKAGE_NAME}/${directory}/.+" \
           >/dev/null
    then

        fail_build "Archive contains runtime data in $directory"
    fi

done


#
# ------------------------------------------------------------
# EXTRACTION TEST
# ------------------------------------------------------------
#

VERIFY_ROOT="$BUILD_ROOT/verify"


mkdir -p "$VERIFY_ROOT" ||
    fail_build "Unable to create verification directory"


tar -xzf \
    "$ARCHIVE" \
    -C "$VERIFY_ROOT" \
    || fail_build "Archive extraction failed"


VERIFY_PACKAGE="$VERIFY_ROOT/$PACKAGE_NAME"


[[ -x "$VERIFY_PACKAGE/lpd.sh" ]] ||
    fail_build "Extracted lpd.sh is not executable"


#
# ------------------------------------------------------------
# EXTRACTED PACKAGE SMOKE TESTS
# ------------------------------------------------------------
#

build_info "Running extracted package smoke tests"


EXTRACTED_VERSION="$(
    "$VERIFY_PACKAGE/lpd.sh" version \
        2>/dev/null
)" || fail_build "Extracted package version command failed"


if [[ "$EXTRACTED_VERSION" != "$LPD_VERSION" ]]; then

    fail_build "Extracted version mismatch: $EXTRACTED_VERSION"
fi


"$VERIFY_PACKAGE/lpd.sh" help \
    >/dev/null \
    2>&1 \
    || fail_build "Extracted package help command failed"


#
# ------------------------------------------------------------
# CHECKSUM VERIFICATION
# ------------------------------------------------------------
#

(
    cd "$DIST_DIR" || exit 1

    sha256sum \
        -c \
        "$(basename "$CHECKSUM")" \
        >/dev/null

) || fail_build "SHA256 verification failed"


#
# ------------------------------------------------------------
# SUCCESS
# ------------------------------------------------------------
#

echo
echo "============================================================"
echo "LPD RELEASE PACKAGE"
echo "============================================================"

printf "Version:   %s\n" "$LPD_VERSION"
printf "Archive:   %s\n" "$ARCHIVE"
printf "Checksum:  %s\n" "$CHECKSUM"

printf "Size:      %s\n" "$(
    du -h "$ARCHIVE" |
    awk '{print $1}'
)"

echo
echo "RESULT: PASS"
