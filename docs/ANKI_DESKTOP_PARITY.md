# Anki 26.08.1 desktop reviewer parity audit

This document compares the Kanki rewrite against the exact pinned Anki desktop reviewer source (`e5a6fbe27fdd4d57d5f712191b4a753032e57853`). It is a handoff-visible list of semantics we must preserve on Kindle and of deliberate omissions.

The goal is not to reproduce Qt. The goal is that scheduling, card HTML/CSS/JS semantics, audio behavior and review state match desktop Anki where the behavior is meaningful to a Kindle reviewer.

## Source references

Primary upstream files/protocols:

- `qt/aqt/reviewer.py`
- `qt/aqt/theme.py`
- `pylib/anki/cards.py`
- `pylib/anki/scheduler/v3.py`
- `pylib/anki/scheduler/legacy.py`
- `proto/anki/scheduler.proto`
- `proto/anki/card_rendering.proto`
- `proto/anki/decks.proto`
- `proto/anki/deck_config.proto`
- `proto/anki/sync.proto`

Kanki equivalents:

- `bridge/anki_bridge.rs`
- `bridge/sync_bridge.rs`
- `assets/reviewer/reviewer.js`
- `assets/device/reviewer-shell.html`
- `device/kanki_device.c`

## Parity matrix

| Area | Desktop Anki 26.08.1 | Kanki rewrite | Status / action |
|---|---|---|---|
| Reviewer document | One initialized reviewer WebView with persistent `#qa` | One persistent reviewer shell and `#qa` | Implemented; verify on PW6 |
| Card body classes | `card cardN isLin` plus theme classes | `card cardN isLin kindle` | Core parity; `kindle` is intentional platform extension |
| Card transition | Replace `#qa`, execute card script in established reviewer runtime | Replace `#qa`, recreate embedded scripts | Implemented; contract test required |
| Question queue | Anki v3 scheduler `get_queued_cards()` | Typed scheduler service with semantic bridge | Implemented; integration evidence pending |
| Scheduler states | Queue-provided states; current custom_data copied to current state | Same pattern in bridge | Implemented; integration evidence pending |
| Answer | Build `CardAnswer` from current queued states and rating | Same typed `CardAnswer` model | Implemented; revlog/state test pending |
| Card body CSS | Note type CSS is authoritative | Note type CSS is authoritative; generic syntax compatibility only | Architectural invariant |
| Platform scaling | Desktop Qt/WebEngine uses CSS pixels/device scale | Lab126 WebKit native CSS-pixel/pixel-density/full-content-zoom path | Implemented feature path; initial-view lifecycle audit below |
| AV extraction | Card question/answer AV tags | Typed `extract_av_tags()` | Implemented; integration evidence pending |
| Replay button | Reviewer-owned semantic control | Reviewer-owned 40px semantic control | Implemented; unrelated SVG must stay untouched |
| Typed answer question | Replace `[[type:...]]` with input using note-field font/size | Bridge implements field/cloze lookup and input replacement | Implemented structurally; fixture evidence pending |
| Typed answer result | Compare typed/correct answer and insert comparison at marker | Bridge calls Anki `compare_answer()` and replaces marker in place | Structurally equivalent; fixture evidence pending |
| Answer separator with FrontSide | Remove `<hr id=answer>` temporarily, then place it immediately before comparison at `[[type:...]]` replacement | Bridge appends separator to the marker-local replacement before `replace_type_markers()` | Structurally equivalent; source contract added |
| Autoplay | `Card.autoplay()` is deck-config driven | Reviewer currently auto-plays first extracted AV tag | **Semantic delta; bridge should expose `!disable_autoplay`** |
| Answer-side question replay | `Card.replay_question_audio_on_answer_side()` is deck-config driven | Current packet exposes answer tags only | **Semantic delta; bridge should expose `!skip_question_when_replaying_answer`** |
| Answer buttons | Pinned v3 scheduler's `answerButtons()` returns 4 | Native bottom bar owns 4 buttons | Equivalent for supported 26.08.1 v3 scheduler; keep interval labels backend-driven |
| Answer intervals | `describe_next_states()` labels | Bridge calls typed `describe_next_states()` | Implemented |
| Card timer | Desktop starts timer on card fetch and uses time limit/options | Bridge records `Instant`; native/UI submission can pass elapsed milliseconds | Core timing implemented; UI semantics verify |
| Bury card | Scheduler bury-card request | Typed `bury_or_suspend_cards()` | Implemented; integration evidence pending |
| Deck collapse | Backend deck metadata | Backend deck metadata | Implemented; hardware persistence test pending |
| Sync ownership | One collection owner; sync through backend lifecycle | Reviewer exits/closes collection before separate sync process | Architectural parity |
| Add-on hooks | Extensive Qt hook surface | Not implemented | Intentional non-goal for 1.0 unless needed by card runtime |
| State customizer JS | Desktop supports `cardStateCustomizer` profile config | Not implemented | Deliberate omission for initial Kindle client; scheduling still comes from Anki |
| Flags/mark/edit/context menu | Desktop reviewer features | Not in initial Kindle scope | Deliberate UI omission, not card-semantic parity blocker |

## Detailed findings

### 1. Persistent `#qa` is required, not optional

Desktop initializes reviewer HTML once and includes:

```html
<div id="qa" dir="auto"></div>
```

Question/answer calls update that established document. Kanki therefore must not return to the historical RAnki pattern of rebuilding an entire HTML document for every side.

### 2. Body classes are card-template semantics

Desktop `body_classes_for_card_ord()` produces `card card{ord+1}` plus platform/theme classes. Templates may rely on `.card1`, `.card2`, etc. Kanki must set the real template ordinal on every side.

`kindle` is an intentional additional class for note authors who choose to target Kindle. It must not be used by Kanki itself as a route to one-deck typography overrides.

### 3. Typed answer separator placement matches desktop structurally

A second source audit corrected an earlier suspicion.

Desktop answer filtering removes `<hr id=answer>` temporarily. If the template uses `{{FrontSide}}`, the comparison replacement at `[[type:...]]` is constructed as:

```html
<hr id=answer>
<div style="font-family: ...; font-size: ...">comparison</div>
```

Kanki's `render_type_answer()` follows the same structural order: it removes the separator from the answer, builds the comparison replacement, prepends `<hr id=answer>` **to that replacement**, then calls `replace_type_markers(&without_separator, &replacement)`. It does not prepend the separator to the whole answer document.

`tests/bridge_source_contract.py` now guards this property so a later refactor cannot accidentally reintroduce the earlier suspected bug.

Still required before the parity gate closes:

- executable fixtures for basic type answer;
- `{{FrontSide}}` type answer;
- cloze type answer;
- unknown/empty field behavior;
- answer scroll target on real Kindle WebKit.

### 4. Autoplay must be data-driven

Desktop `Card.autoplay()` reads the effective deck config. In the current protobuf model the corresponding Rust deck-config field is `disable_autoplay`, so the semantic value Kanki needs is:

```text
autoplay = !deck_config.disable_autoplay
```

Kanki's current reviewer instead automatically plays the first semantic AV tag whenever a packet is shown.

Required design:

- resolve the effective deck config from the card's current/original deck in the typed bridge;
- expose an explicit `autoplay` boolean in the review packet;
- do not infer autoplay from the presence of audio;
- replay buttons remain available when autoplay is off;
- add autoplay-on/off fixtures.

### 5. Answer-side question-audio replay must be represented explicitly

Desktop `Card.replay_question_audio_on_answer_side()` is also deck-config driven. In the current protobuf deck config the storage-oriented field is `skip_question_when_replaying_answer`; the reviewer semantic is therefore:

```text
replay_question_audio_on_answer_side = !deck_config.skip_question_when_replaying_answer
```

Desktop answer replay concatenates question and answer AV tags when that semantic is true.

Required design:

- expose the resolved semantic in `ReviewDto`/prepared-answer data;
- construct the effective answer replay/autoplay queue according to Anki semantics;
- do not make JavaScript reconstruct deck-config inheritance independently;
- test both values, including filtered cards whose effective deck is their original deck.

### 6. Four rating buttons are correct for the pinned v3 scheduler

Desktop reviewer code retains generic rendering branches for 2/3/4 buttons, but the pinned Anki v3 scheduler's `SchedulerBaseWithLegacy.answerButtons()` returns `4`. Kanki is explicitly built on the pinned v3 backend, so a four-button review bar is not currently a parity bug.

Requirements that remain:

- keep the displayed interval text from typed `describe_next_states()` rather than reproducing interval logic in the UI;
- keep rating mapping Again=1, Hard=2, Good=3, Easy=4 aligned with the bridge;
- test all four ratings and revlog/state results.

If a future Anki backend changes v3 button cardinality, treat that as an upstream semantic change during the pinned-version upgrade review instead of pre-implementing obsolete v1/v2 UI behavior.

### 7. Kindle native CSS pixels should be configured at WebView lifecycle level

The current native code calls the Lab126 W3C CSS-pixel/full-content-zoom configuration when entering reviewer mode. Because the WebView is created once and also renders deck/sync pages, the scaling policy should be considered a property of that WebView, not a property of a particular card load.

Before release:

- configure the policy once after WebView creation (or prove that Kindle requires a later lifecycle point);
- record capability/density once per process;
- verify deck, sync and reviewer pages share a coherent coordinate system;
- do not compensate with a synthetic viewport rewrite.

### 8. External links need explicit policy

Desktop Anki controls navigation around its reviewer WebView. Kanki currently intercepts `kanki://` commands, but ordinary HTTP(S) navigation from card HTML needs a deliberate device policy so a dictionary link cannot silently replace the persistent reviewer document.

Before release, choose and test one policy:

- open externally in the Kindle browser/system handler, or
- block and log external navigation in the reviewer.

Never let card link navigation destroy the reviewer lifecycle accidentally.

## Release gate

Any row marked **Semantic delta** remains open in issue #11 until code plus same-commit test evidence exists. Structurally equivalent rows still require executable/real-device evidence where listed. The renderer corpus must include type-answer and autoplay/audio semantics in addition to visual layout fixtures.
