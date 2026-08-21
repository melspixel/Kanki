# Anki 26.08.1 desktop reviewer parity audit

This document compares the Kanki rewrite against the exact pinned Anki desktop reviewer source (`e5a6fbe27fdd4d57d5f712191b4a753032e57853`). It is a handoff-visible list of semantics we must preserve on Kindle and of deliberate omissions.

The goal is not to reproduce Qt. The goal is that scheduling, card HTML/CSS/JS semantics, audio behavior and review state match desktop Anki where the behavior is meaningful to a Kindle reviewer.

## Source references

Primary upstream files/protocols:

- `qt/aqt/reviewer.py`
- `qt/aqt/theme.py`
- `proto/anki/scheduler.proto`
- `proto/anki/card_rendering.proto`
- `proto/anki/decks.proto`
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
| Typed answer question | Replace `[[type:...]]` with input using note-field font/size | Bridge implements field/cloze lookup and input replacement | Near parity; verify cases below |
| Typed answer result | Compare typed/correct answer and insert comparison at marker | Bridge calls Anki `compare_answer()` | **Known placement delta: fix required** |
| Answer separator with FrontSide | Remove `<hr id=answer>` temporarily, then place it immediately before comparison at `[[type:...]]` replacement | Current bridge may prepend separator to complete answer document | **Bug candidate; must fix/test before release** |
| Autoplay | Only when `card.autoplay()` is true | Reviewer currently auto-plays first extracted AV tag | **Semantic delta; requires backend autoplay flag or deliberate decision** |
| Answer-side question replay | If `replay_question_audio_on_answer_side()`, answer replay concatenates question + answer tags | Current packet exposes answer tags only | **Semantic delta; requires packet flag/combined AV behavior** |
| Answer buttons | Desktop can expose 2/3/4 logical buttons depending scheduler/card | Native bottom bar currently always creates 4 buttons | **Semantic delta; needs typed availability/visibility rule** |
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

### 3. Typed answer separator placement is a known discrepancy

Desktop answer filtering removes `<hr id=answer>` temporarily. If the template uses `{{FrontSide}}`, the comparison replacement at `[[type:...]]` is constructed as:

```html
<hr id=answer>
<div style="font-family: ...; font-size: ...">comparison</div>
```

That places the separator **at the type-answer marker**, before the comparison.

The current Kanki bridge removes the separator and, after replacing the marker, may prepend `<hr id=answer>` to the entire answer string. This can move the question/answer separator to the top of the rendered card and is not desktop-equivalent.

Required fix before renderer parity is closed:

- preserve desktop marker-local insertion;
- add fixtures for basic type answer, `{{FrontSide}}`, cloze type answer, unknown field and empty field;
- verify answer scrolling still targets the restored separator.

### 4. Autoplay must be data-driven

Desktop asks `card.autoplay()` before automatically playing question/answer AV tags. Kanki's current reviewer automatically plays the first semantic AV tag when a packet is shown.

Required design:

- expose autoplay decision from the typed bridge/card model;
- do not infer it from presence of audio;
- replay buttons remain available when autoplay is off;
- add autoplay-on/off fixtures.

### 5. Answer-side question-audio replay must be represented explicitly

Desktop answer replay can combine question and answer AV tags when `card.replay_question_audio_on_answer_side()` is enabled.

Required design:

- expose the setting/decision in `ReviewDto` or prepare-answer DTO;
- build the effective answer-side autoplay/replay queue according to Anki semantics;
- do not make the UI reconstruct deck-config rules independently.

### 6. Rating-button cardinality must come from scheduling semantics

Desktop supports 2-, 3- and 4-button cases. The current native shell always owns four physical buttons, which is acceptable as a widget allocation strategy but not as a visibility rule.

Required design:

- semantic backend DTO states which ratings are available for the displayed card;
- hide inapplicable buttons and label applicable buttons with `describe_next_states()` output;
- integration fixtures cover all cardinalities encountered by pinned Anki.

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

Any row marked **Semantic delta**, **Bug candidate** or **Known placement delta** remains open in issue #11 until code plus same-commit test evidence exists. The renderer corpus must include type-answer, autoplay/audio and rating-cardinality cases in addition to visual layout fixtures.
