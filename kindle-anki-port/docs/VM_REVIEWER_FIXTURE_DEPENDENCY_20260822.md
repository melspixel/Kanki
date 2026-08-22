# Reviewer fixture dependency checkpoint — 2026-08-22

## Scope

This is a current-head targeted static-gate checkpoint. It is not a complete release-chain rerun and is not final release evidence.

Starting branch head:

```text
1db00668765a403d1aae32dbc29f7dceaa145358
```

The following current-head blobs were materialized through the GitHub Git object API and independently checked with `git hash-object` before execution:

```text
web/audio_queue.js                         dca58a469c0d32ca0726f8abcb5ede21069ee2ab
web/css_compat.js                          289c98c482f7631efb5b621e5ee378e82ceebb70
web/reviewer.js                            cf18d8aa1f7b6c43b51ca220904019bd793a05a5
tests/test_audio_queue.js                  5982efa9c1a7faca3bc61de7e59f521cca5204d4
tests/test_css_compat_fixtures.js          664a3477078ad81182fb1c80eb7644ccd17c3aa7
tests/test_reviewer_runtime_fixtures.js    256b216269589e3f28be5cb1d02647c3f2cad822
```

VM tools used:

```text
git 2.47.3
node 22.16.0
python 3.13.5
```

## Reproduced failure

Command:

```sh
node tests/test_reviewer_runtime_fixtures.js
```

First failure:

```text
reviewer.js:11
  var audioQueue = window.kapCreateAudioQueue(function (operation, values) {
                          ^

TypeError: window.kapCreateAudioQueue is not a function
```

Root cause: the production reviewer now has an explicit runtime dependency on `web/audio_queue.js`, but the standalone reviewer fixture loaded only `web/reviewer.js`. The canonical static gate executes this test directly, so the current-head gate was not self-contained.

## Fix

`tests/test_reviewer_runtime_fixtures.js` now reads `web/audio_queue.js` and evaluates it in the same VM context immediately before `web/reviewer.js`. This mirrors the production script dependency without duplicating or stubbing audio queue behavior.

Patched test Git blob:

```text
557e094bd7969af8a367ecde6ce9f878c1ce6c2a
```

Patched file SHA-256:

```text
809e7a04fffe152995edf95a270849600086aa2c32925ef418b95ddf99973744
```

## Executed results

```text
node --check web/audio_queue.js                         PASS
node tests/test_audio_queue.js                          PASS: test_audio_queue: ok
node --check web/css_compat.js                          PASS
node tests/test_css_compat_fixtures.js                  PASS: 9 fixtures
node --check web/reviewer.js                            PASS
node --check tests/test_reviewer_runtime_fixtures.js    PASS
node tests/test_reviewer_runtime_fixtures.js            PASS: 10 fixture groups
```

## Remaining gates

This checkpoint does not claim completion of:

- full `run-static-gates.sh`;
- official pinned Anki `cargo check`, 539-test rerun, or release build;
- five real APKG integrations;
- ARMHF rebuild and ELF/GLIBC audit;
- exact PW6 image-derived QEMU;
- packaging or physical PW6 HIL.

The ordinary execution container still has no outbound Git/DNS path and no exact private PW6 rootfs/image pair. GitHub Actions reruns for the starting head failed before recording any job step or log, so they provide no source-test evidence.
