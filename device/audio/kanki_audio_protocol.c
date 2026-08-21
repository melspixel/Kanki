#define _POSIX_C_SOURCE 200809L

#include "kanki_audio_protocol.h"

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int hex_value(char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

static int decode_component(const char *source, size_t length, char *output, size_t capacity) {
    size_t input_index = 0;
    size_t output_index = 0;
    if (!source || !output || capacity == 0) return 0;
    while (input_index < length && output_index + 1 < capacity) {
        if (source[input_index] == '%' && input_index + 2 < length) {
            int high = hex_value(source[input_index + 1]);
            int low = hex_value(source[input_index + 2]);
            if (high >= 0 && low >= 0) {
                int decoded = (high << 4) | low;
                if (decoded == 0) return 0;
                output[output_index++] = (char)decoded;
                input_index += 3;
                continue;
            }
        }
        output[output_index++] = source[input_index] == '+' ? ' ' : source[input_index];
        input_index++;
    }
    output[output_index] = '\0';
    return input_index == length;
}

static int query_has_key(const char *target, const char *key) {
    const char *query = target ? strchr(target, '?') : NULL;
    size_t key_length;
    if (!query || !key) return 0;
    key_length = strlen(key);
    query++;
    while (*query) {
        const char *pair_end = strchr(query, '&');
        const char *equals = strchr(query, '=');
        size_t pair_length = pair_end ? (size_t)(pair_end - query) : strlen(query);
        if (equals && equals < query + pair_length && (size_t)(equals - query) == key_length &&
            strncmp(query, key, key_length) == 0) {
            return 1;
        }
        if (!pair_end) break;
        query = pair_end + 1;
    }
    return 0;
}

int kanki_audio_query_value(const char *target,
                            const char *key,
                            char *output,
                            size_t capacity) {
    const char *query = target ? strchr(target, '?') : NULL;
    size_t key_length;
    if (!query || !key || !output || capacity == 0) return 0;
    key_length = strlen(key);
    query++;
    while (*query) {
        const char *pair_end = strchr(query, '&');
        const char *equals = strchr(query, '=');
        size_t pair_length = pair_end ? (size_t)(pair_end - query) : strlen(query);
        if (equals && equals < query + pair_length && (size_t)(equals - query) == key_length &&
            strncmp(query, key, key_length) == 0) {
            return decode_component(equals + 1,
                                    pair_length - (size_t)(equals + 1 - query),
                                    output,
                                    capacity);
        }
        if (!pair_end) break;
        query = pair_end + 1;
    }
    return 0;
}

static int normalize_speed(const char *input, char output[KANKI_AUDIO_SPEED_CAPACITY]) {
    char *end = NULL;
    double speed;
    int length;
    if (!input || !*input) {
        memcpy(output, "1", 2);
        return 1;
    }
    errno = 0;
    speed = strtod(input, &end);
    if (errno != 0 || !end || *end != '\0' || !isfinite(speed)) return 0;
    if (speed < 0.26) speed = 0.26;
    if (speed > 10.0) speed = 10.0;
    length = snprintf(output, KANKI_AUDIO_SPEED_CAPACITY, "%.9g", speed);
    return length > 0 && length < KANKI_AUDIO_SPEED_CAPACITY;
}

static int optional_value(const char *target,
                          const char *key,
                          char *output,
    size_t capacity) {
    if (kanki_audio_query_value(target, key, output, capacity)) return 1;
    if (query_has_key(target, key)) return 0;
    output[0] = '\0';
    return 1;
}

static int parse_tts_fields(const char *target,
                            const char *language_key,
                            const char *voices_key,
                            const char *speed_key,
                            struct kanki_audio_item *item) {
    char speed[KANKI_AUDIO_SPEED_CAPACITY];
    if (!optional_value(target,
                        language_key,
                        item->language,
                        sizeof(item->language)) ||
        !optional_value(target, voices_key, item->voices, sizeof(item->voices))) {
        return 0;
    }
    if (!kanki_audio_query_value(target, speed_key, speed, sizeof(speed))) {
        if (query_has_key(target, speed_key)) return 0;
        memcpy(speed, "1", 2);
    }
    return normalize_speed(speed, item->speed);
}

int kanki_audio_parse_tts_request(const char *target, struct kanki_audio_item *item) {
    if (!target || !item) return 0;
    memset(item, 0, sizeof(*item));
    item->kind = KANKI_AUDIO_ITEM_TTS;
    if (!kanki_audio_query_value(target, "text", item->value, sizeof(item->value)) ||
        !item->value[0]) {
        return 0;
    }
    return parse_tts_fields(target, "lang", "voices", "speed", item);
}

int kanki_audio_parse_sequence(
    const char *target,
    struct kanki_audio_item items[KANKI_AUDIO_MAX_SEQUENCE_ITEMS],
    size_t *count) {
    char count_value[32];
    char kind[16];
    char key[32];
    char *end = NULL;
    long parsed_count;
    size_t i;

    if (!target || !items || !count ||
        !kanki_audio_query_value(target, "count", count_value, sizeof(count_value))) {
        return 0;
    }
    errno = 0;
    parsed_count = strtol(count_value, &end, 10);
    if (errno != 0 || !end || *end != '\0' || parsed_count < 1 ||
        parsed_count > KANKI_AUDIO_MAX_SEQUENCE_ITEMS) {
        return 0;
    }

    *count = (size_t)parsed_count;
    memset(items, 0, sizeof(*items) * *count);
    for (i = 0; i < *count; i += 1) {
        if (snprintf(key, sizeof(key), "kind%lu", (unsigned long)i) >= (int)sizeof(key) ||
            !kanki_audio_query_value(target, key, kind, sizeof(kind))) {
            return 0;
        }
        if (strcmp(kind, "sound") == 0) {
            items[i].kind = KANKI_AUDIO_ITEM_SOUND;
            memcpy(items[i].speed, "1", 2);
        } else if (strcmp(kind, "tts") == 0) {
            items[i].kind = KANKI_AUDIO_ITEM_TTS;
        } else {
            return 0;
        }
        if (snprintf(key, sizeof(key), "value%lu", (unsigned long)i) >= (int)sizeof(key) ||
            !kanki_audio_query_value(target, key, items[i].value, sizeof(items[i].value)) ||
            !items[i].value[0]) {
            return 0;
        }
        if (items[i].kind == KANKI_AUDIO_ITEM_TTS) {
            char language_key[32];
            char voices_key[32];
            char speed_key[32];
            if (snprintf(language_key, sizeof(language_key), "lang%lu", (unsigned long)i) >=
                    (int)sizeof(language_key) ||
                snprintf(voices_key, sizeof(voices_key), "voices%lu", (unsigned long)i) >=
                    (int)sizeof(voices_key) ||
                snprintf(speed_key, sizeof(speed_key), "speed%lu", (unsigned long)i) >=
                    (int)sizeof(speed_key) ||
                !parse_tts_fields(target, language_key, voices_key, speed_key, &items[i])) {
                return 0;
            }
        }
    }
    return 1;
}
