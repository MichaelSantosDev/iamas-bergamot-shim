// SPDX-License-Identifier: MPL-2.0
// Minimal C ABI over Mozilla bergamot-translator (MPL-2.0) for IAMAS (devplan
// §5.6). One handle = one en→X model (marian intgemm8 alphas + binary
// shortlist + SentencePiece vocab[s]) and its own single-threaded
// BlockingService. Calls on one handle must not overlap; the Dart side runs
// every call on one background isolate.
#ifndef IMAS_BERGAMOT_SHIM_H_
#define IMAS_BERGAMOT_SHIM_H_

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define BG_API __declspec(dllexport)
#else
#define BG_API __attribute__((visibility("default")))
#endif

typedef struct bg_translator bg_translator;

/// ABI version of this shim (bumped on any signature change).
BG_API int bg_abi_version(void);

/// Loads a model. `vocab_trg` may be NULL or equal to `vocab_src` (shared
/// vocab). `lex` may be NULL (no shortlist; slower). `config_yaml` may be
/// NULL or extra marian-decoder options in YAML ("beam-size: 1\n...") that
/// override the defaults. Returns NULL on failure; see bg_last_error().
BG_API bg_translator* bg_load(const char* model, const char* lex, const char* vocab_src,
                              const char* vocab_trg, const char* config_yaml);

/// Translates UTF-8 text (multi-sentence, line breaks kept). Returns a
/// malloc'ed UTF-8 string the caller must release with bg_free_string(), or
/// NULL on failure (see bg_last_error()).
BG_API char* bg_translate(bg_translator* handle, const char* utf8_text);

/// Releases a string returned by bg_translate().
BG_API void bg_free_string(char* s);

/// Unloads the model and frees the handle. NULL is a no-op.
BG_API void bg_free(bg_translator* handle);

/// Last error message on the calling thread ("" when none). Valid until the
/// next bg_* call on this thread.
BG_API const char* bg_last_error(void);

#ifdef __cplusplus
}
#endif

#endif  // IMAS_BERGAMOT_SHIM_H_
