// SPDX-License-Identifier: MPL-2.0
#include "bergamot_shim.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <memory>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "common/logging.h"
#include "translator/parser.h"
#include "translator/response.h"
#include "translator/response_options.h"
#include "translator/service.h"
#include "translator/translation_model.h"

using marian::bergamot::BlockingService;
using marian::bergamot::Response;
using marian::bergamot::ResponseOptions;
using marian::bergamot::TranslationModel;

struct bg_translator {
  std::unique_ptr<BlockingService> service;
  std::shared_ptr<TranslationModel> model;
};

namespace {

thread_local std::string g_last_error;

void setError(const std::string& e) { g_last_error = e; }

// YAML double-quoted scalar (paths may contain spaces / colons).
std::string quote(const char* s) {
  std::string out = "\"";
  for (const char* p = s; *p; ++p) {
    if (*p == '"' || *p == '\\') out += '\\';
    out += *p;
  }
  return out + "\"";
}

// The Firefox Translations engine settings (translations-engine.worker.mjs),
// with alignment off (we only need text) and a single CPU worker.
const char* kDefaults =
    "beam-size: 1\n"
    "normalize: 1.0\n"
    "word-penalty: 0\n"
    "max-length-break: 128\n"
    "mini-batch-words: 1024\n"
    "workspace: 128\n"
    "max-length-factor: 2.0\n"
    "skip-cost: true\n"
    "cpu-threads: 0\n"
    "quiet: true\n"
    "quiet-translation: true\n"
    "gemm-precision: int8shiftAlphaAll\n"
    "ssplit-mode: paragraph\n";

}  // namespace

extern "C" {

int bg_abi_version(void) { return 1; }

const char* bg_last_error(void) { return g_last_error.c_str(); }

bg_translator* bg_load(const char* model, const char* lex, const char* vocab_src, const char* vocab_trg,
                       const char* config_yaml) {
  g_last_error.clear();
  if (model == nullptr || vocab_src == nullptr) {
    setError("model and vocab_src are required");
    return nullptr;
  }
  // A bad file must surface as an error, never std::abort() the app.
  marian::setThrowExceptionOnAbort(true);
  try {
    std::ostringstream yaml;
    yaml << kDefaults;
    yaml << "models:\n  - " << quote(model) << "\n";
    yaml << "vocabs:\n  - " << quote(vocab_src) << "\n  - "
         << quote(vocab_trg != nullptr && *vocab_trg ? vocab_trg : vocab_src) << "\n";
    if (lex != nullptr && *lex) {
      yaml << "shortlist:\n  - " << quote(lex) << "\n  - false\n";
    }
    std::string config = yaml.str();
    if (config_yaml != nullptr && *config_yaml) {
      // Later keys win: parse defaults + overrides as one YAML map would
      // reject duplicates, so merge by dropping overridden default lines.
      std::string extra = config_yaml;
      std::istringstream lines(config);
      std::ostringstream merged;
      std::string line;
      while (std::getline(lines, line)) {
        auto colon = line.find(':');
        if (colon != std::string::npos && line[0] != ' ') {
          std::string key = line.substr(0, colon + 1);
          if (("\n" + extra).find("\n" + key) != std::string::npos) continue;
        }
        merged << line << "\n";
      }
      merged << extra;
      if (extra.back() != '\n') merged << "\n";
      config = merged.str();
    }
    auto options = marian::bergamot::parseOptionsFromString(config, /*validate=*/false);
    auto t = std::make_unique<bg_translator>();
    BlockingService::Config serviceConfig;
    serviceConfig.cacheSize = 0;
    serviceConfig.logger.level = "off";
    t->service = std::make_unique<BlockingService>(serviceConfig);
    t->model = std::make_shared<TranslationModel>(options, /*replicas=*/1);
    return t.release();
  } catch (const std::exception& e) {
    setError(e.what());
  } catch (...) {
    setError("unknown error while loading the model");
  }
  return nullptr;
}

char* bg_translate(bg_translator* handle, const char* utf8_text) {
  g_last_error.clear();
  if (handle == nullptr || utf8_text == nullptr) {
    setError("null handle or text");
    return nullptr;
  }
  try {
    std::vector<std::string> sources{std::string(utf8_text)};
    std::vector<ResponseOptions> opts(1);
    std::vector<Response> responses = handle->service->translateMultiple(handle->model, std::move(sources), opts);
    const std::string& out = responses.at(0).target.text;
    char* buf = static_cast<char*>(std::malloc(out.size() + 1));
    if (buf == nullptr) {
      setError("out of memory");
      return nullptr;
    }
    std::memcpy(buf, out.data(), out.size());
    buf[out.size()] = '\0';
    return buf;
  } catch (const std::exception& e) {
    setError(e.what());
  } catch (...) {
    setError("unknown error while translating");
  }
  return nullptr;
}

void bg_free_string(char* s) { std::free(s); }

void bg_free(bg_translator* handle) {
  if (handle == nullptr) return;
  try {
    handle->model.reset();
    handle->service.reset();
  } catch (...) {
  }
  delete handle;
}

}  // extern "C"
