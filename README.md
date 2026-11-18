# libimas_bergamot

A small shared library with a C ABI (`bergamot_shim.h`) over Mozilla's
**bergamot-translator**, the engine behind Firefox Translations. IAMAS uses it
for the first MT step of the §5.6 cascade (`BergamotProvider` in
`lib/src/translation/bergamot/`).

```c
bg_translator* bg_load(model, lex, vocab_src, vocab_trg /*NULL = shared*/, config_yaml /*NULL*/);
char*          bg_translate(handle, utf8_text);   // free with bg_free_string()
void           bg_free(handle);
const char*    bg_last_error(void);               // thread-local
int            bg_abi_version(void);              // 1
```

One handle holds one en→X model and its own single-threaded
`BlockingService`. Calls on a handle must not overlap; Dart runs them on one
background isolate. Marian `ABORT`s become errors (`setThrowExceptionOnAbort`),
so a bad model file never kills the app. Decoder settings are the Firefox
engine's (`beam-size 1`, `gemm-precision int8shiftAlphaAll`, shortlist on,
`ssplit-mode paragraph`, so line breaks are kept).

## Source and licences

| Component | Where | Licence |
|---|---|---|
| bergamot-translator (`inference/`) | [mozilla/translations](https://github.com/mozilla/translations) @ `69455acaecbe8650cdba988dbcf7c10ca20e7c48` (BERGAMOT_VERSION v0.6.0) | MPL-2.0 |
| marian-fork | same repo, `inference/marian-fork` | MIT |
| ruy (ARM int8 GEMM + SGEMM) | submodule `google/ruy` | Apache-2.0 |
| intgemm (x86 only, not built for ARM) | submodule `kpu/intgemm` | MIT |
| simd_utils | submodule `browsermt/simd_utils` | BSD-2-Clause |
| sentencepiece | submodule `browsermt/sentencepiece` | Apache-2.0 |
| ssplit-cpp | submodule `browsermt/ssplit-cpp` | Apache-2.0 (nonbreaking-prefix files LGPL-2.1, not used/bundled) |
| PCRE2 10.39 (for ssplit) | GitHub release tarball, SHA-256 pinned | BSD-3-Clause |
| this shim + scripts | here | MPL-2.0 |

`mozilla/bergamot-translator` itself was last updated in 2022 and has no ARM
backend; the maintained code (with ruy for ARM) lives in `mozilla/translations`.

## Build

```bash
./build_android.sh      # → prebuilt/android-arm64/libimas_bergamot.so  (NDK r28/r29, API 26)
./build_macos.sh        # → prebuilt/macos-arm64/libimas_bergamot.dylib  (Apple Silicon host)
```

Both call `fetch_sources.sh`, which clones the pinned revision with only the
five submodules a CPU build needs (~550 MB checkout, `$BERGAMOT_SRC`, default
`./.src`), applies `patches/`, and unpacks the verified PCRE2 tarball so the
CMake build itself needs no network. Then CMake (the Android SDK's 3.22.1 +
Ninja when present) builds only `imas_bergamot` with `-j6` (`JOBS`). A clean
fetch + build takes ~1.5–2 min on an M2 Pro; the build tree is ~280 MB
(`$BUILD_DIR`, default `./.build/<target>`). Defaults: `MinSizeRel` (`-Os`;
`BUILD_TYPE=Release` gives `-O3`: +9 % size, ~6 % faster), function/data
sections + `--gc-sections`, hidden visibility (only `bg_*` exported), static
libc++, stripped, 16 KB page alignment.

**Reproducible.** Paths are mapped out of the binary (`-ffile-prefix-map`)
and the GNU build-id is off, so two checkouts in different directories give
a byte-identical `.so` (verified: SHA-256
`95b74e35c05cd922813737d40cf76e6e423cfcf5b46608dc7c36706d3e0577ff`, NDK
29.0.14206865).

Patches (build fixes only, idempotent):

* `sentencepiece-clang21-constexpr-enum.patch`: clang ≥ 20 (Xcode 26, NDK
  r28+) rejects an out-of-range enum value in a `constexpr`.
* `pathie-android-api26.patch`: `glob(3)` and `iconv(3)` exist in bionic only
  from API 28 and the app's minSdk is 26. Android file names are UTF-8, and
  `Path::glob()` is never used by inference.

| Artifact | Size |
|---|---|
| `libimas_bergamot.so` (android arm64-v8a) | 6.73 MB (stored uncompressed in the APK) |
| `libimas_bergamot.dylib` (macOS arm64) | 5.64 MB |

## How the app gets it (native assets)

`packages/imas_ai/hook/build.dart` registers the library as a code asset
(`package:imas_ai/imas_bergamot`) for **android arm64** and **macOS arm64**.
Other targets (armeabi-v7a, x86_64, iOS) get nothing and `BergamotProvider`
reports itself unsupported, so the cascade moves on to OPUS-MT.

Mode, set in the workspace `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    imas_ai:
      bergamot: auto     # default | source | off
```

* `auto`: use `prebuilt/<target>/` when a developer has built it, otherwise
  run the build script into `.dart_tool/hooks_runner/shared/imas_ai/build/bergamot/`
  (cached across builds; `flutter clean` does not touch it, deleting
  `.dart_tool` does). The NDK comes from the hook's C compiler config.
* `source`: always build from source.
* `off`: bundle nothing.

`prebuilt/`, `.src/` and `.build/` are git-ignored: the repository carries
only sources and scripts.

**F-Droid recipe:** NDK r29 + the SDK's CMake 3.22.1 in `srclibs`/`ndk:`,
network for `fetch_sources.sh` (or pre-run it in `prebuild` and point
`BERGAMOT_SRC` at a `srclib`), then the normal `flutter build apk --flavor
floss`; the hook builds the library from source. `scandelete` nothing: no
binaries are committed.

## Host tests

```bash
./build_macos.sh
IMAS_BERGAMOT_DIR=/path/to/models flutter test test/bergamot_test.dart
```

`IMAS_BERGAMOT_DIR` holds `enes/`, `enpt/`, `enfr/`, `ende/`, each with the
Firefox file names (`model.enes.intgemm.alphas.bin`, `lex.50.50.enes.s2t.bin`,
`vocab.enes.spm`). `IMAS_BERGAMOT_LIBRARY` overrides the library path.

## About this repository

This repository publishes the source of `libimas_bergamot`, the MPL-2.0 shim
used by the IAMAS app (https://iamas.app) for on-device translation, as
required by the Mozilla Public License 2.0. The rest of the IAMAS app is
proprietary and not included here. Contact: suporte@iamas.app
