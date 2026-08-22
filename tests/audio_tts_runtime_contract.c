#include "kanki_tts_player.h"

#include <stdio.h>

int main(void) {
    int result = kanki_tts_runtime_probe();
    if (result != 0) {
        fprintf(stderr, "audio TTS runtime contract failed: probe status=%d\n", result);
        return 1;
    }
    result = kanki_tts_play("hello \"world\" !", "en_US", "Samantha,Fallback", "0.75");
    if (result != 0) {
        fprintf(stderr, "audio TTS runtime contract failed: playback status=%d\n", result);
        return 1;
    }
    puts("audio TTS runtime contract: pass");
    return 0;
}
