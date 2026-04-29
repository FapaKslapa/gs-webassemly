#!/usr/bin/env bash

set -euo pipefail

GS_VERSION="${GS_VERSION:-dedddcb}"
GS_GIT_URL="${GS_GIT_URL:-https://github.com/ArtifexSoftware/ghostpdl.git}"
MAKE_JOBS="${MAKE_JOBS:-$(nproc 2>/dev/null || echo 2)}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
BUILD_ID="${BUILD_ID:-}"
CLEAN_OUTPUT="${CLEAN_OUTPUT:-0}"
WORK_DIR="${WORK_DIR:-/build/work}"
PATCHES_DIR="${PATCHES_DIR:-/build/patches}"
DEBUG="${DEBUG:-0}"
EXPORTS_STYLE="${EXPORTS_STYLE:-list}"

log() { printf '\n\033[1;36m[gs-wasm]\033[0m %s\n' "$*"; }
err() { printf '\n\033[1;31m[gs-wasm:ERROR]\033[0m %s\n' "$*" >&2; }
ok()  { printf '\n\033[1;32m[gs-wasm:OK]\033[0m %s\n' "$*"; }

command -v emconfigure >/dev/null 2>&1 || { err "emconfigure not found"; exit 1; }
command -v autoconf    >/dev/null 2>&1 || { err "autoconf not found"; exit 1; }
[ -f "${PATCHES_DIR}/arch/wasm.h" ] || { err "Missing patch: ${PATCHES_DIR}/arch/wasm.h"; exit 1; }

if [ -n "${BUILD_ID}" ]; then
    OUTPUT_DIR="${OUTPUT_DIR}/${BUILD_ID}"
fi

if [ "${CLEAN_OUTPUT}" = "1" ] && [ -d "${OUTPUT_DIR}" ]; then
    log "Cleaning output directory: ${OUTPUT_DIR}"
    rm -rf "${OUTPUT_DIR:?}"/*
fi

mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"
GS_DIR="${WORK_DIR}/ghostpdl-${GS_VERSION}"

is_commit_hash() { [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]; }
if [ ! -d "${GS_DIR}" ]; then
    if [ "${GS_VERSION}" = "latest" ]; then
        log "Cloning ghostpdl (HEAD)"
        git clone --depth 1 "${GS_GIT_URL}" "${GS_DIR}"
        ( cd "${GS_DIR}" && NOCONFIGURE=1 ./autogen.sh )
    elif is_commit_hash "${GS_VERSION}"; then
        log "Cloning ghostpdl for checkout ${GS_VERSION}"
        git clone "${GS_GIT_URL}" "${GS_DIR}"
        ( cd "${GS_DIR}" && git checkout "${GS_VERSION}" && NOCONFIGURE=1 ./autogen.sh )
    else
        TARBALL="${WORK_DIR}/ghostpdl-${GS_VERSION}.tar.gz"
        URL="https://github.com/ArtifexSoftware/ghostpdl/archive/refs/tags/ghostpdl-${GS_VERSION}.tar.gz"
        log "Downloading ghostpdl ${GS_VERSION}"
        curl -fL -o "${TARBALL}" "${URL}"
        mkdir -p "${WORK_DIR}/_extract"
        tar -xzf "${TARBALL}" -C "${WORK_DIR}/_extract"
        EXTRACTED="$(find "${WORK_DIR}/_extract" -maxdepth 1 -mindepth 1 -type d | head -n1)"
        mv "${EXTRACTED}" "${GS_DIR}"
        rm -rf "${WORK_DIR}/_extract"
    fi
fi
[ -d "${GS_DIR}/.git" ] && log "Ghostpdl commit: $(cd "${GS_DIR}" && git rev-parse HEAD)"

log "Applying patches"
cp -a "${PATCHES_DIR}/." "${GS_DIR}/"

log "Running emconfigure"
( cd "${GS_DIR}" && emconfigure ./configure \
    --disable-threading --disable-cups --disable-dbus --disable-gtk \
    --with-drivers=PS CC=emcc CCAUX=gcc \
    --with-arch_h=arch/wasm.h --without-tesseract )

log "Patching Makefile"
awk '{ if ($0 == "LDFLAGSAUX=$(LDFLAGS)") print "#" $0; else print $0 }' \
    "${GS_DIR}/Makefile" > "${GS_DIR}/Makefile.tmp"
mv "${GS_DIR}/Makefile.tmp" "${GS_DIR}/Makefile"

case "${EXPORTS_STYLE}" in
    list) EXPORTS_FLAG="-sEXPORTED_RUNTIME_METHODS=FS,callMain" ;;
    json) EXPORTS_FLAG="-sEXPORTED_RUNTIME_METHODS=['FS','callMain']" ;;
    *) err "Invalid EXPORTS_STYLE: ${EXPORTS_STYLE}"; exit 1 ;;
esac
EXTRA_LDFLAGS="${EXPORTS_FLAG} -sFORCE_FILESYSTEM=1"

for d in "${GS_DIR}/bin" "${GS_DIR}/debugbin"; do
    if [ -f "$d/gs" ] && ! grep -qE 'Module\["FS"\]|Module\.FS|"FS":|callMain' "$d/gs" 2>/dev/null; then
        rm -f "$d/gs" "$d/gs.wasm"
    fi
done

if [ "${DEBUG}" = "1" ]; then
    log "Build DEBUG"
    ( cd "${GS_DIR}" && \
        XCFLAGS="-g -Wbad-function-cast -Wcast-function-type" \
        XLDFLAGS="-sERROR_ON_UNDEFINED_SYMBOLS=0 -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1 -sASSERTIONS=1 ${EXTRA_LDFLAGS} -o gs.js --emit-symbol-map -g3" \
        emmake make debug -j"${MAKE_JOBS}" )
    BIN_DIR="${GS_DIR}/debugbin"
else
    log "Build RELEASE"
    ( cd "${GS_DIR}" && \
        XLDFLAGS="-sERROR_ON_UNDEFINED_SYMBOLS=0 -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1 ${EXTRA_LDFLAGS} -o gs.js" \
        emmake make -j"${MAKE_JOBS}" )
    BIN_DIR="${GS_DIR}/bin"
fi

[ -f "${BIN_DIR}/gs.wasm" ] && [ -f "${BIN_DIR}/gs" ] || { err "Output missing in ${BIN_DIR}"; exit 1; }
log "Copying artifacts to ${OUTPUT_DIR}"
cp "${BIN_DIR}/gs.wasm" "${OUTPUT_DIR}/gs.wasm"
cp "${BIN_DIR}/gs"      "${OUTPUT_DIR}/gs.js"
( cd "${OUTPUT_DIR}" && sha256sum gs.js gs.wasm > SHA256SUMS )

ls -la "${OUTPUT_DIR}"
cat "${OUTPUT_DIR}/SHA256SUMS"
