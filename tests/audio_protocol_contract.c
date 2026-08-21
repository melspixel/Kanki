#include "kanki_audio_protocol.h"

#include <stdio.h>
#include <string.h>

static int require(int condition, const char *message) {
    if (condition) return 1;
    fprintf(stderr, "audio protocol contract failed: %s\n", message);
    return 0;
}

int main(void) {
    static const char request[] =
        "/sequence?count=2&kind0=sound&value0=folder%2Fa+b.mp3&kind1=tts&"
        "value1=Bonjour+%26+goodbye&lang1=fr_FR&voices1=Lea%2CFallback&speed1=0.75";
    struct kanki_audio_item items[KANKI_AUDIO_MAX_SEQUENCE_ITEMS];
    struct kanki_audio_item single;
    size_t count = 0;

    if (!require(kanki_audio_parse_sequence(request, items, &count),
                 "valid typed sequence was rejected") ||
        !require(count == 2, "sequence count changed") ||
        !require(items[0].kind == KANKI_AUDIO_ITEM_SOUND, "sound kind changed") ||
        !require(strcmp(items[0].value, "folder/a b.mp3") == 0, "sound source decode changed") ||
        !require(items[1].kind == KANKI_AUDIO_ITEM_TTS, "TTS kind changed") ||
        !require(strcmp(items[1].value, "Bonjour & goodbye") == 0, "TTS text was lost") ||
        !require(strcmp(items[1].language, "fr_FR") == 0, "TTS language was lost") ||
        !require(strcmp(items[1].voices, "Lea,Fallback") == 0, "TTS voices were lost") ||
        !require(strcmp(items[1].speed, "0.75") == 0, "TTS speed was lost")) {
        return 1;
    }

    if (!require(kanki_audio_parse_tts_request(
                     "/tts?text=single+request&lang=de_DE&voices=Vicki&speed=1.25",
                     &single),
                 "valid single TTS request was rejected") ||
        !require(strcmp(single.value, "single request") == 0, "single TTS text changed") ||
        !require(strcmp(single.language, "de_DE") == 0, "single TTS language changed") ||
        !require(strcmp(single.voices, "Vicki") == 0, "single TTS voice changed") ||
        !require(strcmp(single.speed, "1.25") == 0, "single TTS speed changed") ||
        !require(!kanki_audio_parse_sequence("/sequence?count=17", items, &count),
                 "unbounded sequence was accepted") ||
        !require(!kanki_audio_parse_tts_request("/tts?text=x&speed=nan", &single),
                 "non-finite TTS speed was accepted") ||
        !require(!kanki_audio_parse_tts_request("/tts?text=x&lang=%00", &single),
                 "embedded NUL was accepted") ||
        !require(kanki_audio_parse_tts_request("/tts?text=x&speed=0.1", &single),
                 "native speed clamp request was rejected") ||
        !require(strcmp(single.speed, "0.26") == 0, "native minimum speed was not clamped")) {
        return 1;
    }

    puts("audio native protocol contract: pass");
    return 0;
}
