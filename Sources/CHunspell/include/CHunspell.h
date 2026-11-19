#ifndef CHUNSPELL_H
#define CHUNSPELL_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle owning a Hunspell dictionary instance.
typedef struct CHunspellHandle CHunspellHandle;

/// Returns the version string of the embedded Hunspell engine.
const char *chunspell_bridge_version(void);

/// Creates a Hunspell dictionary instance from `.aff` and `.dic` file paths.
/// Returns NULL if either path is null, empty, unreadable, or fails to initialize.
CHunspellHandle *chunspell_create(const char *aff_path, const char *dic_path);

/// Destroys a Hunspell dictionary instance created with `chunspell_create`.
void chunspell_destroy(CHunspellHandle *handle);

/// Checks whether a UTF-8 NFC word is accepted by the Hunspell dictionary.
bool chunspell_spell(CHunspellHandle *handle, const char *word);

/// Generates spelling suggestions for a UTF-8 NFC word.
/// Caller must release `out_suggestions` with `chunspell_free_list`.
size_t chunspell_suggest(CHunspellHandle *handle, const char *word, char ***out_suggestions);

/// Frees a suggestion array previously returned by `chunspell_suggest`.
void chunspell_free_list(CHunspellHandle *handle, char **suggestions, size_t count);

/// Adds a UTF-8 NFC word dynamically to the runtime dictionary session.
/// Returns 0 on success or -1 on invalid input.
int chunspell_add(CHunspellHandle *handle, const char *word);

#ifdef __cplusplus
}
#endif

#endif /* CHUNSPELL_H */
