#!/usr/bin/env bash
# Fetches the pinned bergamot-translator sources (mozilla/translations,
# directory inference/) with only the submodules a CPU build needs, plus the
# PCRE2 tarball ssplit-cpp would otherwise download during the build.
#
#   fetch_sources.sh [DEST]      (default: $BERGAMOT_SRC or ./.src)
#
# Prints the inference/ directory to pass as -DBERGAMOT_SOURCE_DIR.
set -euo pipefail

# mozilla/translations main, 2026-09-25 (BERGAMOT_VERSION v0.6.0).
TRANSLATIONS_REPO="https://github.com/mozilla/translations.git"
TRANSLATIONS_REV="69455acaecbe8650cdba988dbcf7c10ca20e7c48"
PCRE2_VERSION="10.39"
PCRE2_SHA256="0781bd2536ef5279b1943471fdcdbd9961a2845e1d2c9ad849b9bd98ba1a9bd4"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${1:-${BERGAMOT_SRC:-$here/.src}}"
src="$dest/translations"

if [ ! -d "$src/.git" ]; then
  mkdir -p "$dest"
  git init -q "$src"
  git -C "$src" remote add origin "$TRANSLATIONS_REPO"
fi
if [ "$(git -C "$src" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$TRANSLATIONS_REV" ]; then
  git -C "$src" fetch -q --depth 1 --filter=blob:none origin "$TRANSLATIONS_REV"
  git -C "$src" sparse-checkout set inference >/dev/null
  git -C "$src" checkout -q --detach "$TRANSLATIONS_REV"
fi

# Only what a CPU build needs: no fbgemm, nccl, onnxjs, emsdk, websocket.
for sm in \
  inference/3rd_party/ssplit-cpp \
  inference/marian-fork/src/3rd_party/sentencepiece \
  inference/marian-fork/src/3rd_party/intgemm \
  inference/marian-fork/src/3rd_party/ruy \
  inference/marian-fork/src/3rd_party/simd_utils; do
  git -C "$src" submodule update -q --init --depth 1 "$sm"
done

# Local patches (idempotent): build fixes for current toolchains only.
#  - sentencepiece: clang >= 20 (Xcode 26, NDK r28+) made an out-of-range
#    enum value in a constexpr a hard error; `constexpr` → `const`.
apply_patch() { # <repo dir> <patch>
  if git -C "$1" apply --check "$2" 2>/dev/null; then
    git -C "$1" apply "$2"
  elif ! git -C "$1" apply --check -R "$2" 2>/dev/null; then
    echo "patch does not apply: $2" >&2
    exit 1
  fi
}
#  - pathie-cpp: glob(3) and iconv(3) exist in bionic only from API 28 (app
#    minSdk 26). Android file names are UTF-8 (no iconv needed) and
#    Path::glob() is never used for inference, so it throws there.
apply_patch "$src/inference/marian-fork/src/3rd_party/sentencepiece" \
  "$here/patches/sentencepiece-clang21-constexpr-enum.patch"
apply_patch "$src" "$here/patches/pathie-android-api26.patch"

# PCRE2 (BSD-3-Clause) for ssplit-cpp, verified, unpacked where its
# FindPCRE2.cmake looks so the build itself needs no network.
pcre_dir="$src/inference/3rd_party/ssplit-cpp/src/3rd-party/pcre2-$PCRE2_VERSION"
if [ ! -f "$pcre_dir/configure" ]; then
  tarball="$dest/pcre2-$PCRE2_VERSION.tar.gz"
  curl -fsSL -o "$tarball" \
    "https://github.com/PhilipHazel/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz"
  got="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"
  if [ "$got" != "$PCRE2_SHA256" ]; then
    echo "pcre2 sha256 mismatch: $got" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$pcre_dir")"
  tar -xzf "$tarball" -C "$(dirname "$pcre_dir")"
  rm -f "$tarball"
fi

echo "$src/inference"
