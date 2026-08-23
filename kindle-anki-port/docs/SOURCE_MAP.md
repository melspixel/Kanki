# Desktop Anki source map

Every shipped behavior has an official upstream owner and a parity gate.

| Desktop owner | Responsibility | Port owner | Verification |
|---|---|---|---|
| `rslib/src/collection/` | collection, schema, transactions, undo | official `anki` crate | open/close/recovery integration |
| `rslib/src/scheduler/` + scheduler proto | queue, intervals, answer, bury | `core/src/port.rs` typed adapter | scheduler parity fixtures |
| `rslib/src/card_rendering/` + card-rendering proto | templates, AV, comparison, cloze | official service calls | renderer/type-answer fixtures |
| `rslib/src/media/` | media filenames/checks | official core + URI adapter | Unicode/traversal tests |
| `rslib/src/sync/`, sync proto, `aqt/sync.py` | normal/full/media sync | `core/src/port.rs` semantic ABI + `native/sync.c` worker | mocked protocol + opt-in account gate |
| `qt/aqt/reviewer.py` | reviewer phases, autoplay, type answer, timing | `core/src/port.rs` | state transition suite |
| `qt/aqt/webview.py` | command bridge/focus/lifecycle | `native/app.c`, `web/bridge.js` | protocol/fuzz tests |
| desktop reviewer TypeScript under `ts/` | DOM replacement/replay/input | `web/reviewer.js` | jsdom parity + ES5 gate |
| `qt/aqt/sound.py` + AV proto | AV queue/replay | `native/audio.c` | queue/device-loss tests |
| `qt/aqt/main.py` | app state/shutdown | `native/app.c`, `scripts/launch.sh` | repeated lifecycle test |

## Porting rule

Desktop Anki behavior is the source of truth. Kindle-specific code may replace
a platform primitive, but may not reinterpret scheduling, rendering,
typed-answer comparison, sync decisions or card semantics.
