#include "CHunspell.h"
#include "hunspell.hxx"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <unistd.h>
#include <vector>

struct CHunspellHandle {
    std::unique_ptr<Hunspell> engine;
};

const char *chunspell_bridge_version(void) {
    return HUNSPELL_VERSION_STRING;
}

CHunspellHandle *chunspell_create(const char *aff_path, const char *dic_path) {
    if (aff_path == nullptr || dic_path == nullptr || aff_path[0] == '\0' || dic_path[0] == '\0') {
        return nullptr;
    }

    // Verify readability before calling Hunspell, because Hunspell's constructor
    // otherwise silently succeeds with an empty dictionary on missing paths.
    if (access(aff_path, R_OK) != 0 || access(dic_path, R_OK) != 0) {
        return nullptr;
    }

    try {
        auto engine = std::make_unique<Hunspell>(aff_path, dic_path);
        auto handle = new CHunspellHandle{std::move(engine)};
        return handle;
    } catch (...) {
        return nullptr;
    }
}

void chunspell_destroy(CHunspellHandle *handle) {
    delete handle;
}

bool chunspell_spell(CHunspellHandle *handle, const char *word) {
    if (handle == nullptr || handle->engine == nullptr || word == nullptr || word[0] == '\0') {
        return false;
    }

    return handle->engine->spell(std::string(word));
}

size_t chunspell_suggest(CHunspellHandle *handle, const char *word, char ***out_suggestions) {
    if (out_suggestions == nullptr) {
        return 0;
    }
    *out_suggestions = nullptr;

    if (handle == nullptr || handle->engine == nullptr || word == nullptr || word[0] == '\0') {
        return 0;
    }

    std::vector<std::string> suggestions = handle->engine->suggest(std::string(word));
    if (suggestions.empty()) {
        return 0;
    }

    const size_t count = suggestions.size();
    char **list = static_cast<char **>(std::malloc(count * sizeof(char *)));
    if (list == nullptr) {
        return 0;
    }

    for (size_t i = 0; i < count; ++i) {
        char *copy = strdup(suggestions[i].c_str());
        if (copy == nullptr) {
            for (size_t j = 0; j < i; ++j) {
                std::free(list[j]);
            }
            std::free(list);
            return 0;
        }
        list[i] = copy;
    }

    *out_suggestions = list;
    return count;
}

void chunspell_free_list(CHunspellHandle *handle, char **suggestions, size_t count) {
    (void)handle;
    if (suggestions == nullptr) {
        return;
    }

    for (size_t i = 0; i < count; ++i) {
        std::free(suggestions[i]);
    }
    std::free(suggestions);
}

int chunspell_add(CHunspellHandle *handle, const char *word) {
    if (handle == nullptr || handle->engine == nullptr || word == nullptr || word[0] == '\0') {
        return -1;
    }

    return handle->engine->add(std::string(word));
}
