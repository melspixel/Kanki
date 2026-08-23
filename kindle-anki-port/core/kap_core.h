#ifndef KAP_CORE_H
#define KAP_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KapCore KapCore;

void kap_string_free(char *value);
char *kap_build_info_json(void);
KapCore *kap_core_new(char **error_out);
void kap_core_free(KapCore *core);
char *kap_open_collection_json(KapCore *core, const char *collection_path,
                               const char *media_folder_path, const char *media_db_path);
char *kap_close_collection_json(KapCore *core);
char *kap_deck_tree_json(KapCore *core);
char *kap_set_current_deck_json(KapCore *core, int64_t deck_id);
char *kap_set_deck_collapsed_json(KapCore *core, int64_t deck_id, uint8_t collapsed);
char *kap_next_question_json(KapCore *core);
char *kap_reveal_answer_json(KapCore *core, const char *typed_answer);
char *kap_answer_json(KapCore *core, uint32_t rating, uint32_t milliseconds_taken);
char *kap_bury_current_json(KapCore *core);
char *kap_sync_collection_json(KapCore *core, const char *hkey,
                               const char *endpoint, uint8_t sync_media,
                               uint32_t io_timeout_secs);
char *kap_full_sync_json(KapCore *core, const char *hkey, const char *endpoint,
                         uint8_t upload, int32_t server_media_usn,
                         uint8_t has_server_media_usn,
                         uint32_t io_timeout_secs);
char *kap_media_sync_status_json(KapCore *core);
char *kap_abort_sync_json(KapCore *core);
char *kap_health_json(KapCore *core);

#ifdef __cplusplus
}
#endif

#endif
