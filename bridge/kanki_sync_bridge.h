#ifndef KANKI_SYNC_BRIDGE_H
#define KANKI_SYNC_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KankiSyncCore KankiSyncCore;

KankiSyncCore *kanki_sync_core_new(char **error_out);
void kanki_sync_core_free(KankiSyncCore *core);

char *kanki_sync_open_collection_json(KankiSyncCore *core,
                                      const char *collection_path,
                                      const char *media_folder_path,
                                      const char *media_db_path);
char *kanki_sync_close_collection_json(KankiSyncCore *core);
char *kanki_sync_login_json(KankiSyncCore *core,
                            const char *username,
                            const char *password,
                            const char *endpoint);
char *kanki_sync_collection_json(KankiSyncCore *core,
                                 const char *hkey,
                                 const char *endpoint,
                                 uint8_t sync_media);
char *kanki_sync_full_json(KankiSyncCore *core,
                           const char *hkey,
                           const char *endpoint,
                           uint8_t upload,
                           int32_t server_media_usn,
                           uint8_t have_server_media_usn);
char *kanki_sync_media_json(KankiSyncCore *core,
                            const char *hkey,
                            const char *endpoint);
char *kanki_sync_media_status_json(KankiSyncCore *core);
char *kanki_sync_abort_json(KankiSyncCore *core);

#ifdef __cplusplus
}
#endif

#endif
