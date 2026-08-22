#ifndef KANKI_BRIDGE_H
#define KANKI_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KankiCore KankiCore;

/* All *_json functions return an owned UTF-8 JSON envelope. */
void kanki_string_free(char *value);
char *kanki_build_info_json(void);

KankiCore *kanki_core_new(char **error_out);
void kanki_core_free(KankiCore *core);

char *kanki_open_collection_json(KankiCore *core,
                                 const char *collection_path,
                                 const char *media_folder_path,
                                 const char *media_db_path);
char *kanki_close_collection_json(KankiCore *core);
char *kanki_deck_tree_json(KankiCore *core);
char *kanki_set_current_deck_json(KankiCore *core, int64_t deck_id);
char *kanki_set_deck_collapsed_json(KankiCore *core, int64_t deck_id, uint8_t collapsed);
char *kanki_next_card_json(KankiCore *core);
char *kanki_prepare_answer_json(KankiCore *core, const char *typed_answer);
char *kanki_answer_json(KankiCore *core, uint32_t rating, uint32_t milliseconds_taken);
char *kanki_bury_current_json(KankiCore *core);
char *kanki_health_json(KankiCore *core);

#ifdef __cplusplus
}
#endif

#endif
