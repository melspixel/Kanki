#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEWER = (ROOT / "assets/reviewer/reviewer.js").read_text(encoding="utf-8")
SERVER = (ROOT / "device/audio/kanki_audio_server.c").read_text(encoding="utf-8")


def require(text: str, fragment: str, message: str) -> None:
    if fragment not in text:
        raise SystemExit(message)


def forbid(text: str, fragment: str, message: str) -> None:
    if fragment in text:
        raise SystemExit(message)


require(REVIEWER, "playTags: function (tags)", "reviewer must support semantic AV sequences")
require(REVIEWER, "audioPing('sequence', sequenceValues(tags));", "reviewer must send one ordered autoplay sequence")
require(REVIEWER, "if (packet.autoplay && packet.autoplay_audio", "autoplay must be controlled by explicit backend semantic")
require(REVIEWER, "prepared.replay_question_audio_on_answer_side", "answer autoplay must honor question-replay semantic")
require(REVIEWER, "questionAudio.concat(answerAudio)", "answer replay queue must preserve question-then-answer order")
forbid(REVIEWER, "if (packet.audio && packet.audio.length) playTag(packet.audio[0])", "autoplay must not infer/play only first AV tag")

require(SERVER, "#define MAX_SEQUENCE_ITEMS 16", "audio sequence count must be bounded")
require(SERVER, "static int parse_sequence", "audio server must parse semantic sequence requests")
require(SERVER, "static int start_sequence_job", "audio server must own one ordered playback job")
require(SERVER, "for (i = 0; i < count; i += 1)", "sequence child must play items in order")
require(SERVER, 'strncmp(target, "/sequence?", 10)', "loopback protocol must expose sequence endpoint")
require(SERVER, "stop_active_job();\n    pid = fork();", "new sequences must replace prior active playback atomically")

# The sequence endpoint remains loopback-only through the same server bind and
# does not introduce shell execution for untrusted card values.
require(SERVER, "address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);", "audio server must bind loopback only")
forbid(SERVER, "system(", "audio server must not execute shell commands")
forbid(SERVER, "popen(", "audio server must not execute shell pipelines")

print("audio semantic sequence contract: pass")
