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
- `device/audio/kanki_audio_protocol.c`
- `device/audio/kanki_tts_player.c`

## Parity matrix

| Area | Desktop Anki 26.08.1 | Kanki rewrite | Status / action |
|---|---|---|---|
| Reviewer document | One initialized reviewer WebView with persistent `#qa` | One persistent reviewer shell and `#qa` | Implemented; verify on PW6 |
| Card body classes | `card cardN isLin` plus theme classes | `card cardN isLin kindle` | Core parity; `kindle` is intentional platform extension |
| Card transition | Replace `#qa`, execute card script in established reviewer runtime | Replace `#qa`, recreate embedded scripts | Synthetic and seven fixed upstream-APKG host transitions pass; verify on PW6 |
| Question queue | Anki v3 scheduler `get_queued_cards()` | Typed scheduler service with semantic bridge | Synthetic and seven separately imported upstream APKG queues pass |
| Scheduler states | Queue-provided states; current custom_data copied to current state | Same pattern in bridge | Four-rating disposable integration passes |
| Answer | Build `CardAnswer` from current queued states and rating | Same typed `CardAnswer` model | Again/Hard/Good/Easy revlog persistence passes |
| Card body CSS | Note type CSS is authoritative | Note type CSS is authoritative; generic syntax compatibility only | Architectural invariant |
| Flex item order | `order` accepts integers with initial value 0 | Non-negative integers map to old WebKit ordinal groups starting at 1; the original declaration is retained and negative values do not emit invalid legacy groups | Host contract passes; full negative-order emulation and PW6 geometry remain open |
| MathJax | Lazily load MathJax, clear prior typeset state and await typesetting scoped to `#qa` before the shown hook | Load pinned MathJax 2.7.9 once, clear prior jax and await SVG typesetting scoped to persistent `#qa` before UI state/diagnostics | Real vendor host contract passes; PW6 geometry/performance pending |
| Platform scaling | Desktop Qt/WebEngine uses CSS pixels/device scale | Lab126 WebKit native CSS-pixel/pixel-density/full-content-zoom path configured once per persistent WebView | Executable native lifecycle contract and fixed-rootfs symbol/loader audit pass; PW6 computed geometry pending |
| AV extraction | Card question/answer AV tags | Typed `extract_av_tags()` after partial render and semantic `FrontSide` expansion | Synthetic sound/TTS plus fixed upstream `media.apkg` sound pass; COCA/user/PW6 evidence pending |
| TTS metadata/runtime | Preserve text, language, preferred voices and speed; select an available host voice | Direct and ordered protocols preserve all fields; fixed-PW6 adapter sets `textsource`, `voicelang` and clamped native `speed` on `ttssrc` before `mixersink` | Executable browser/parser/fake-runtime contracts pass; PW6 exposes no voice-ID property, and audible language/routing evidence remains open |
| Replay button | Reviewer-owned semantic control | Reviewer-owned 40px semantic control | Implemented; unrelated SVG must stay untouched |
| Typed answer question | Replace `[[type:...]]` with input using note-field font/size | Bridge implements field/cloze lookup and input replacement | Basic/cloze plus known-empty/unknown-field disposable fixtures pass; PW6 pending |
| Typed answer result | Compare typed/correct answer and insert comparison at marker | Bridge calls Anki `compare_answer()` and replaces marker in place | Basic and backend-extracted cloze comparisons pass; PW6 pending |
| Answer separator with FrontSide | Remove `<hr id=answer>` temporarily, then place it immediately before comparison at `[[type:...]]` replacement | Bridge appends separator to the marker-local replacement before `replace_type_markers()` | Source contract and executable basic `FrontSide` fixture pass |
| Autoplay | `Card.autoplay()` is deck-config driven | Typed effective-deck boolean controls one bounded ordered AV sequence | Enabled/disabled and filtered original-deck integration pass; PW6 pending |
| Answer-side question replay | `Card.replay_question_audio_on_answer_side()` is deck-config driven | Prepared answer conditionally queues question tags before answer tags | Enabled/disabled and filtered original-deck integration pass; PW6 pending |
| Answer buttons | Pinned v3 scheduler's `answerButtons()` returns 4 | Native bottom bar owns 4 buttons | Equivalent for supported 26.08.1 v3 scheduler; keep interval labels backend-driven |
| Answer intervals | `describe_next_states()` labels | Bridge calls typed `describe_next_states()` | Implemented |
| Card timer | Desktop starts timer on card fetch and uses time limit/options | Bridge records `Instant`; native/UI submission can pass elapsed milliseconds | Core timing implemented; UI semantics verify |
| Bury card | Scheduler bury-card request | Typed `bury_or_suspend_cards()` | User-bury persistence passes in disposable integration |
| Deck collapse | Backend deck metadata | Backend deck metadata | Implemented; hardware persistence test pending |
| Sync ownership | One collection owner; sync through backend lifecycle | Reviewer exits/closes collection before separate sync process; both inherit/acquire one kernel operation lock | Controlled loopback full/normal/media lifecycle plus host and fixed-PW6-rootfs lock contention/handoff/lifetime pass; live AnkiWeb/PW6 lifecycle pending |
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

At `c2a513f1acdcc1cf778515374e2aef58d9099eb2`, disposable fixtures exercise
basic and cloze input/comparison, `{{FrontSide}}` placement, a known field with
an empty value, an unknown-field marker, rating and close/reopen through the
production bridge. The cloze expected value comes from pinned Anki's
`extract_cloze_for_typing()`; the bridge does not reproduce cloze parsing.
The unknown-field fixture uses a stale rendered marker because valid current
templates referencing an unknown field are rejected earlier by the pinned
backend.

Still required before the parity gate closes: input focus/keyboard behavior and
the answer scroll target on real Kindle WebKit.

### 4. Autoplay must be data-driven

Desktop `Card.autoplay()` reads the effective deck config. In the current protobuf model the corresponding Rust deck-config field is `disable_autoplay`, so the semantic value Kanki needs is:

```text
autoplay = !deck_config.disable_autoplay
```

At `dc53cc89603428b5b41bc9b223dc07a6222c2f65`, Kanki resolves this boolean in
the typed bridge and the reviewer starts one ordered AV sequence only when it
is true. Replay buttons remain independent of autoplay. The pinned-backend
fixture covers the enabled default and a disabled normal deck whose card Anki
moves into a filtered deck; the packet remains disabled by the original deck.

Remaining evidence:

- native sequence playback and repeated replay on PW6/AirPods.

### 5. Answer-side question-audio replay must be represented explicitly

Desktop `Card.replay_question_audio_on_answer_side()` is also deck-config driven. In the current protobuf deck config the storage-oriented field is `skip_question_when_replaying_answer`; the reviewer semantic is therefore:

```text
replay_question_audio_on_answer_side = !deck_config.skip_question_when_replaying_answer
```

Desktop answer replay concatenates question and answer AV tags when that semantic is true.

At `dc53cc89603428b5b41bc9b223dc07a6222c2f65`, prepared-answer data carries
the resolved boolean and question tags. The persistent reviewer concatenates
question then answer tags only when it is true; host fixtures cover both
values. The pinned-backend fixture confirms that both the question packet and
prepared answer remain disabled when a card is reviewed from a filtered deck
whose original normal deck disables question replay.

Remaining evidence:

- ordered native playback on PW6/AirPods.

### 6. Four rating buttons are correct for the pinned v3 scheduler

Desktop reviewer code retains generic rendering branches for 2/3/4 buttons, but the pinned Anki v3 scheduler's `SchedulerBaseWithLegacy.answerButtons()` returns `4`. Kanki is explicitly built on the pinned v3 backend, so a four-button review bar is not currently a parity bug.

Requirements that remain:

- keep the displayed interval text from typed `describe_next_states()` rather than reproducing interval logic in the UI;
- keep rating mapping Again=1, Hard=2, Good=3, Easy=4 aligned with the bridge;
- preserve the passing disposable integration for all four ratings and revlog
  persistence as the fixture corpus expands.

If a future Anki backend changes v3 button cardinality, treat that as an upstream semantic change during the pinned-version upgrade review instead of pre-implementing obsolete v1/v2 UI behavior.

### 7. Kindle native CSS pixels should be configured at WebView lifecycle level

Because one WebView renders deck, reviewer and sync pages, its scaling policy is
a property of that WebView, not of a particular card load. The earlier native
path loaded deck/sync before configuration and repeated configuration on every
reviewer entry. At `47946f7b64b52124cfe3db8c1e32dcd85310d6d4`, production
`build_window()` configures the feature-detected Lab126 W3C CSS-pixel,
pixel-density, full-content-zoom and zoom-level path once after the persistent
WebView exists and before any document loads.

The executable native lifecycle contract drives multiple deck/reviewer/sync
transitions through a fake UI ABI and proves the configuration is neither early
nor repeated. The fixed PW6 rootfs loader audit resolves the four actual
firmware symbols. Still required before release:

- verify deck, sync and reviewer pages share a coherent computed coordinate
  system on physical PW6;
- retain one capability/density record per process;
- do not compensate with a synthetic viewport rewrite.

### 8. External links need explicit policy

Desktop Anki controls navigation around its reviewer WebView. At
`868b07a15ec09be2790f97e339e4a7984c8a7afb`, Kanki applies the chosen initial
policy at two layers: delegated reviewer JavaScript cancels external link
defaults, and native WebKit policy blocks external/default navigation after
the reviewer is ready. Same-document `file:`/`about:` fragments and card
JavaScript remain allowed. Diagnostics record only the URI scheme, not a full
potentially sensitive URI.

The host navigation contract passes. PW6 still needs to prove the native
policy callback and persistent reviewer lifecycle under real WebKit.

### 9. MathJax completion is part of the reviewer transition

Pinned desktop Anki's `ts/reviewer/index.ts` detects inline/block delimiters,
loads its MathJax runtime once, clears prior typeset state and awaits
`typesetPromise([qa])` before publishing the shown side. Kanki preserves that
lifecycle boundary while selecting MathJax 2.7.9 with SVG output for the older
Kindle WebKit. Formula layout remains a reviewer capability; backend HTML and
note CSS remain authoritative.

At `4b11acb9cb2c029c1349093683ee1335a1295149`, the checksum-verified upstream
distribution typesets inline and display formulas across successive dynamic
updates of the same `#qa`. Host contracts also prove stale callbacks cannot
publish state for a newer side and that ordinary SVG/image attributes remain
unchanged. This is not PW6 acceptance: old-WebKit geometry, long-card scroll,
formula performance and idle behavior remain hardware gates.

### 10. Original packages must remain inputs, not compatibility patches

At `96b326c0da1fdcbe96f519ac84f3f1f985ec403e`, Kanki inventories and
checksum-verifies the seven unmodified APKGs available in pinned Anki's public
test corpus. Each is imported by the semantic typed Anki service into a fresh
disposable collection, queued/rendered by the production bridge, and shown on
both sides in one persistent reviewer `#qa`. Note-type CSS is passed through
verbatim; the test adds no deck/note-type selectors. `media.apkg` proves the
imported `foo.wav` path becomes typed AV without changing ordinary media.

These small upstream fixtures prove the generic boundary, but they are not a
substitute for original COCA, an unrelated rich user deck, or Kindle WebKit
computed geometry. Those inputs are absent from the repository and remain
explicit PW6/corpus gates; they must never be rewritten to make Kanki pass.

## Release gate

Any row marked **Semantic delta** remains open in issue #11 until code plus same-commit test evidence exists. Structurally equivalent rows still require executable/real-device evidence where listed. The renderer corpus must include type-answer and autoplay/audio semantics in addition to visual layout fixtures.
