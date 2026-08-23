#!/bin/sh
set -eu
PROJECT_ROOT=${PROJECT_ROOT:?}
LAUNCHER="$PROJECT_ROOT/scripts/launch.sh"
sh -n "$LAUNCHER"
grep -q '/proc/' "$LAUNCHER" || {
    echo 'launcher must verify process identity via /proc' >&2
    exit 1
}
grep -Eq 'SIGUSR1|USR1' "$LAUNCHER" || {
    echo 'launcher must raise a live instance' >&2
    exit 1
}
