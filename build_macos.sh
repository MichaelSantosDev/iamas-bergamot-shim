#!/usr/bin/env bash
# Builds libimas_bergamot.dylib for macOS arm64 (host tests / desktop). Run it
# on an Apple Silicon Mac: marian-fork's TargetArch.cmake rejects
# CMAKE_OSX_ARCHITECTURES=arm64, so the host architecture is used.
#
#   build_macos.sh [OUT_DIR]     (default: ./prebuilt/macos-arm64)
#
# Env: BERGAMOT_SRC (sources dir for fetch_sources.sh), BUILD_DIR (default
# ./.build/macos-arm64), JOBS (default 6), CMAKE (default: Android SDK
# CMake 3.22.1 if present, else cmake on PATH; the bundled PCRE2 10.39 needs
# CMake < 4 or CMAKE_POLICY_VERSION_MINIMUM, which we also pass), BUILD_TYPE
# (default MinSizeRel).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:-$here/prebuilt/macos-arm64}"
build="${BUILD_DIR:-$here/.build/macos-arm64}"
jobs="${JOBS:-6}"
sdk_cmake="${ANDROID_HOME:-$HOME/Library/Android/sdk}/cmake/3.22.1/bin"
if [ -z "${CMAKE:-}" ]; then
  if [ -x "$sdk_cmake/cmake" ]; then CMAKE="$sdk_cmake/cmake"; else CMAKE=cmake; fi
fi
generator=()
if [ -x "$sdk_cmake/ninja" ]; then generator=(-G Ninja -DCMAKE_MAKE_PROGRAM="$sdk_cmake/ninja");
elif command -v ninja >/dev/null; then generator=(-G Ninja); fi

export MACOSX_DEPLOYMENT_TARGET=11.0  # also for the PCRE2 external project
src="$("$here/fetch_sources.sh")"

"$CMAKE" -S "$here" -B "$build" "${generator[@]}" \
  -DBERGAMOT_SOURCE_DIR="$src" \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE:-MinSizeRel}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
"$CMAKE" --build "$build" --target imas_bergamot -j "$jobs"

mkdir -p "$out"
cp "$build/libimas_bergamot.dylib" "$out/libimas_bergamot.dylib"
strip -x "$out/libimas_bergamot.dylib"
install_name_tool -id "@rpath/libimas_bergamot.dylib" "$out/libimas_bergamot.dylib"
codesign --force -s - "$out/libimas_bergamot.dylib" >/dev/null 2>&1 || true
ls -l "$out/libimas_bergamot.dylib"
