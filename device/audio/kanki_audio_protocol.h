#ifndef KANKI_AUDIO_PROTOCOL_H
#define KANKI_AUDIO_PROTOCOL_H

#include <stddef.h>

#define KANKI_AUDIO_MAX_SEQUENCE_ITEMS 16
#define KANKI_AUDIO_TEXT_CAPACITY 8192
#define KANKI_AUDIO_LANGUAGE_CAPACITY 128
#define KANKI_AUDIO_VOICES_CAPACITY 1024
#define KANKI_AUDIO_SPEED_CAPACITY 32

enum kanki_audio_item_kind {
    KANKI_AUDIO_ITEM_SOUND = 0,
    KANKI_AUDIO_ITEM_TTS = 1,
};

struct kanki_audio_item {
    enum kanki_audio_item_kind kind;
    char value[KANKI_AUDIO_TEXT_CAPACITY];
    char language[KANKI_AUDIO_LANGUAGE_CAPACITY];
    char voices[KANKI_AUDIO_VOICES_CAPACITY];
    char speed[KANKI_AUDIO_SPEED_CAPACITY];
};

int kanki_audio_query_value(const char *target,
                            const char *key,
                            char *output,
                            size_t capacity);

int kanki_audio_parse_tts_request(const char *target, struct kanki_audio_item *item);

int kanki_audio_parse_sequence(
    const char *target,
    struct kanki_audio_item items[KANKI_AUDIO_MAX_SEQUENCE_ITEMS],
    size_t *count);

#endif
