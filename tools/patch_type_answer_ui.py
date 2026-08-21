#!/usr/bin/env python3
"""One-shot source migration for the rewrite-v1 typed-answer UI contract.

This intentionally edits only source-owned Kanki files and asserts the old
contracts before replacing them. It is safe to re-run: already-migrated files
are left unchanged.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"{label}: expected source contract not found")
    return text.replace(old, new, 1)


def patch_device() -> None:
    path = ROOT / "device/kanki_device.c"
    text = path.read_text()
    text = replace_once(
        text,
        "    char *(*next_card)(KankiCore *);\n    char *(*answer)(KankiCore *, uint32_t, uint32_t);",
        "    char *(*next_card)(KankiCore *);\n    char *(*prepare_answer)(KankiCore *, const char *);\n    char *(*answer)(KankiCore *, uint32_t, uint32_t);",
        "device ABI field",
    )
    text = replace_once(
        text,
        '    LOAD_REQUIRED(app->backend_lib, &app->backend, next_card, "kanki_next_card_json");\n'
        '    LOAD_REQUIRED(app->backend_lib, &app->backend, answer, "kanki_answer_json");',
        '    LOAD_REQUIRED(app->backend_lib, &app->backend, next_card, "kanki_next_card_json");\n'
        '    LOAD_REQUIRED(app->backend_lib, &app->backend, prepare_answer, "kanki_prepare_answer_json");\n'
        '    LOAD_REQUIRED(app->backend_lib, &app->backend, answer, "kanki_answer_json");',
        "device ABI loader",
    )
    text = replace_once(
        text,
        '    } else if (strcmp(command, "review/next") == 0) {\n'
        '        send_next_card(app);\n'
        '    } else if (strcmp(command, "review/answer") == 0) {',
        '    } else if (strcmp(command, "review/next") == 0) {\n'
        '        send_next_card(app);\n'
        '    } else if (strcmp(command, "review/show-answer") == 0) {\n'
        '        char *typed = query_value(uri, "typed");\n'
        '        char *response;\n'
        '        if (!typed) typed = duplicate_string("");\n'
        '        if (!typed) {\n'
        '            send_local_error(app, "kankiDevice", "show_answer", "out of memory");\n'
        '        } else {\n'
        '            response = app->backend.prepare_answer(app->core, typed);\n'
        '            send_response(app, "kankiDevice", "show_answer", response);\n'
        '        }\n'
        '        free(typed);\n'
        '    } else if (strcmp(command, "review/answer") == 0) {',
        "device show-answer route",
    )
    text = replace_once(
        text,
        '    execute_script(app, "if(window.kankiDevice){window.kankiDevice.showAnswer();}");',
        '    execute_script(app, "if(window.kankiDevice){window.kankiDevice.requestShowAnswer();}");',
        "device Show Answer button",
    )
    path.write_text(text)


def patch_reviewer() -> None:
    path = ROOT / "assets/reviewer/reviewer.js"
    text = path.read_text()
    if "function requestShowAnswer()" not in text:
        marker = "  function showCard(packet) {\n"
        if marker not in text:
            raise SystemExit("reviewer showCard contract not found")
        text = text.replace(
            marker,
            "  function requestShowAnswer() {\n"
            "    if (!currentCard) return false;\n"
            "    var input = document.getElementById('typeans');\n"
            "    command('review/show-answer', {typed: input ? input.value : ''});\n"
            "    return false;\n"
            "  }\n\n"
            "  function wireTypeAnswer() {\n"
            "    var input = document.getElementById('typeans');\n"
            "    if (!input) return;\n"
            "    input.onkeypress = function (event) {\n"
            "      event = event || window.event;\n"
            "      if (event && (event.keyCode === 13 || event.which === 13)) {\n"
            "        return requestShowAnswer();\n"
            "      }\n"
            "      return true;\n"
            "    };\n"
            "    if (input.focus) input.focus();\n"
            "  }\n\n"
            + marker,
            1,
        )
    text = replace_once(
        text,
        "      executeScripts(qa);\n      installSemanticAudio(packet);\n      if (packet.side === 'answer') {",
        "      executeScripts(qa);\n      installSemanticAudio(packet);\n      if (packet.side === 'question') wireTypeAnswer();\n      if (packet.side === 'answer') {",
        "reviewer type-input wiring",
    )
    old = (
        "  function showAnswer() {\n"
        "    if (!currentCard) return;\n"
        "    showCard(packet(currentCard, 'answer'));\n"
        "    command('ui/state', {\n"
        "      mode: 'answer',\n"
        "      again: currentCard.intervals && currentCard.intervals[0] || '',\n"
        "      hard: currentCard.intervals && currentCard.intervals[1] || '',\n"
        "      good: currentCard.intervals && currentCard.intervals[2] || '',\n"
        "      easy: currentCard.intervals && currentCard.intervals[3] || '',\n"
        "      ms: Math.max(0, new Date().getTime() - shownAt)\n"
        "    });\n"
        "  }\n"
    )
    new = (
        "  function showPreparedAnswer(prepared) {\n"
        "    if (!currentCard || !prepared) return;\n"
        "    showCard({\n"
        "      side: 'answer',\n"
        "      body_class: 'card card' + (Number(currentCard.template_ordinal || 0) + 1) + ' isLin kindle',\n"
        "      html: prepared.html || '',\n"
        "      css: currentCard.css || '',\n"
        "      audio: prepared.audio || []\n"
        "    });\n"
        "    command('ui/state', {\n"
        "      mode: 'answer',\n"
        "      again: currentCard.intervals && currentCard.intervals[0] || '',\n"
        "      hard: currentCard.intervals && currentCard.intervals[1] || '',\n"
        "      good: currentCard.intervals && currentCard.intervals[2] || '',\n"
        "      easy: currentCard.intervals && currentCard.intervals[3] || '',\n"
        "      ms: Math.max(0, new Date().getTime() - shownAt)\n"
        "    });\n"
        "  }\n"
    )
    text = replace_once(text, old, new, "reviewer prepared-answer rendering")
    text = replace_once(
        text,
        "      if (name === 'next_card') {\n",
        "      if (name === 'show_answer') {\n"
        "        showPreparedAnswer(envelope.data);\n"
        "      } else if (name === 'next_card') {\n",
        "reviewer native prepared-answer response",
    )
    text = replace_once(
        text,
        "    nativeResponse: nativeResponse,\n    showAnswer: showAnswer,\n    currentElapsedMilliseconds:",
        "    nativeResponse: nativeResponse,\n    requestShowAnswer: requestShowAnswer,\n    currentElapsedMilliseconds:",
        "reviewer public API",
    )
    path.write_text(text)


def patch_test() -> None:
    path = ROOT / "tests/renderer_contract.test.cjs"
    text = path.read_text()
    if 'id="typeans"' not in text:
        text = text.replace(
            "    '<span id=\"sound-marker\">[anki:play:q:0]</span>' +\n",
            "    '<span id=\"sound-marker\">[anki:play:q:0]</span><input id=\"typeans\" value=\"typed\">' +\n",
            1,
        )
    old = (
        "window.kankiDevice.showAnswer();\n"
        "assert.strictEqual(document.getElementById('qa'), qa, 'answer must not reload the page');\n"
        "assert.strictEqual(window.__answerRuns, 1, 'answer scripts must execute after insertion');\n"
        "assert.strictEqual(document.getElementById('answer-text').textContent, 'answer');\n"
        "assert.deepStrictEqual(hostValue(audio[2]), ['tts', 'answer', 'en_US', [], 1]);\n"
        "assert.strictEqual(document.querySelectorAll('.replay-button').length, 1);\n"
    )
    new = (
        "const typeInput = document.getElementById('typeans');\n"
        "assert.ok(typeInput, 'typed-answer input must remain usable in the question');\n"
        "assert.strictEqual(typeof typeInput.onkeypress, 'function');\n\n"
        "window.kankiDevice.nativeResponse(\n"
        "  'show_answer',\n"
        "  JSON.stringify({\n"
        "    ok: true,\n"
        "    data: {html: card.answer_html, audio: card.answer_audio},\n"
        "    error: null,\n"
        "  }),\n"
        ");\n"
        "assert.strictEqual(document.getElementById('qa'), qa, 'answer must not reload the page');\n"
        "assert.strictEqual(window.__answerRuns, 1, 'answer scripts must execute after insertion');\n"
        "assert.strictEqual(document.getElementById('answer-text').textContent, 'answer');\n"
        "assert.deepStrictEqual(hostValue(audio[2]), ['tts', 'answer', 'en_US', [], 1]);\n"
        "assert.strictEqual(document.querySelectorAll('.replay-button').length, 1);\n"
    )
    text = replace_once(text, old, new, "renderer answer contract")
    path.write_text(text)


patch_device()
patch_reviewer()
patch_test()
