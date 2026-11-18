#!/usr/bin/env bash
# Builds libimas_bergamot.so for Android arm64-v8a with the NDK (ruy GEMM,
# no x86 intgemm, no Apple Accelerate). This is the step an F-Droid recipe
# runs before `flutter build apk --flavor floss`.
#
#   build_android.sh [OUT_DIR]   (default: ./prebuilt/android-arm64)
#
# Env: ANDROID_NDK (default: newest r28/r29 under $ANDROID_HOME/ndk),
# ANDROID_PLATFORM (default android-26 = app minSdk), BERGAMOT_SRC,
# BUILD_DIR (default ./.build/android-arm64), JOBS (default 6), CMAKE,
# BUILD_TYPE (default MinSizeRel: -Os, 9 % smaller .so than -O3 for ~6 %
# more time per sentence).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:-$here/prebuilt/android-arm64}"
build="${BUILD_DIR:-$here/.build/android-arm64}"
jobs="${JOBS:-6}"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ndk="${ANDROID_NDK:-$(ls -d "$sdk"/ndk/2[89].* 2>/dev/null | sort -V | tail -1)}"
[ -d "$ndk" ] || { echo "Android NDK not found (set ANDROID_NDK)" >&2; exit 1; }
sdk_cmake="$sdk/cmake/3.22.1/bin"
if [ -z "${CMAKE:-}" ]; then
  if [ -x "$sdk_cmake/cmake" ]; then CMAKE="$sdk_cmake/cmake"; else CMAKE=cmake; fi
fi
generator=()
if [ -x "$sdk_cmake/ninja" ]; then generator=(-G Ninja -DCMAKE_MAKE_PROGRAM="$sdk_cmake/ninja");
elif command -v ninja >/dev/null; then generator=(-G Ninja); fi

src="$("$here/fetch_sources.sh")"

"$CMAKE" -S "$here" -B "$build" "${generator[@]}" \
  -DBERGAMOT_SOURCE_DIR="$src" \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE:-MinSizeRel}" \
  -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM="${ANDROID_PLATFORM:-android-26}" \
  -DANDROID_STL=c++_static \
  -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
"$CMAKE" --build "$build" --target imas_bergamot -j "$jobs"

host_tag="$(ls "$ndk/toolchains/llvm/prebuilt" | head -1)"
mkdir -p "$out"
"$ndk/toolchains/llvm/prebuilt/$host_tag/bin/llvm-strip" --strip-unneeded \
  -o "$out/libimas_bergamot.so" "$build/libimas_bergamot.so"
ls -l "$out/libimas_bergamot.so"
