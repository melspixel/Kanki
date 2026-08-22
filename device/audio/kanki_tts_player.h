#ifndef KANKI_TTS_PLAYER_H
#define KANKI_TTS_PLAYER_H

int kanki_tts_runtime_probe(void);

int kanki_tts_play(const char *text,
                   const char *language,
                   const char *voices,
                   const char *speed);

#endif
