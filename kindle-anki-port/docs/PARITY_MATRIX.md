# Reviewer parity matrix

| Feature | Desktop source | Implementation | Automated evidence | Hardware evidence |
|---|---|---|---|---|
| Question/answer phase | `aqt/reviewer.py` | core state machine | `core_contract` | pending device run |
| Scheduling/intervals | rslib scheduler | official backend | ARM integration | pending device run |
| Body classes/CSS | desktop reviewer | persistent shell | `reviewer_contract` | pending screenshots |
| Inline card scripts | desktop webview | script rehydration | `reviewer_contract` | pending cards |
| Sound and replay | AV tags/sound player | semantic packet/audio worker | `reviewer_contract`, audio tests | pending Bluetooth |
| Typed answer | reviewer type filters | official cloze/compare calls | `reviewer_contract`, core tests | pending keyboard |
| Long cards | desktop scroll surface | one scroll root + page gesture | `reviewer_contract` | pending touch |
| Exit/re-enter | desktop app state | verified PID + raise/clean close | lifecycle shell test | pending 50 cycles |
| Sync | rslib/desktop sync | official sync adapter | protocol fixtures | pending real account |
