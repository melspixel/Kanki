#!/bin/sh
set -eu
PROJECT_ROOT=${PROJECT_ROOT:?set PROJECT_ROOT}
CC=${CC:-cc}
TMP=$(mktemp -d)
wrapper1=
wrapper2=
first=
second=
unrelated=
cleanup() {
    set +e
    for pid in "$first" "$second" "$wrapper1" "$wrapper2" "$unrelated"; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
    for pid in "$wrapper1" "$wrapper2" "$unrelated"; do
        [ -n "$pid" ] && wait "$pid" 2>/dev/null || true
    done
    rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP/ext/run" "$TMP/ext/logs" "$TMP/data"
cat >"$TMP/fake_app.c" <<'APP'
#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static volatile sig_atomic_t raised;
static volatile sig_atomic_t stopped;
static void on_usr1(int sig) { (void)sig; raised = 1; }
static void on_stop(int sig) { (void)sig; stopped = 1; }
static void append(const char *path, const char *line) {
    FILE *file = fopen(path, "a");
    if (!file) _exit(90);
    fputs(line, file);
    fputc('\n', file);
    fclose(file);
}
int main(void) {
    const char *log = getenv("KAP_SIGNAL_LOG");
    if (!log) return 64;
    signal(SIGUSR1, on_usr1);
    signal(SIGTERM, on_stop);
    signal(SIGINT, on_stop);
    signal(SIGHUP, on_stop);
    append(log, "START");
    while (!stopped) {
        pause();
        if (raised) {
            raised = 0;
            append(log, "USR1");
        }
    }
    return 0;
}
APP
"$CC" -O2 -std=c99 -Wall -Wextra -Werror "$TMP/fake_app.c" -o "$TMP/ext/kap-app"
printf '{"build_commit":"launcher-integration-test"}\n' >"$TMP/ext/BUILD.json"

export KAP_APP_DIR="$TMP/ext"
export KAP_DATA_DIR="$TMP/data"
export KAP_APP_BIN="$TMP/ext/kap-app"
export KAP_PID_FILE="$TMP/ext/run/kap-app.pid"
export KAP_LOG_FILE="$TMP/ext/logs/launch.log"
export KAP_SYNC_REQUEST="$TMP/ext/run/.sync-request"
export KAP_OPENED_BUILD_FILE="$TMP/ext/run/.opened-build"
export KAP_OPERATION_LOCK_DIR="$TMP/ext/run/.kap-operation.lock"
export KAP_SIGNAL_LOG="$TMP/signals"

wait_for_pidfile() {
    attempts=0
    while [ "$attempts" -lt 200 ]; do
        if [ -s "$KAP_PID_FILE" ]; then
            pid=$(cat "$KAP_PID_FILE" 2>/dev/null || true)
            case "$pid" in
                ''|*[!0-9]*) ;;
                *) kill -0 "$pid" 2>/dev/null && { printf '%s\n' "$pid"; return 0; } ;;
            esac
        fi
        attempts=$((attempts + 1))
        sleep 0.02
    done
    return 1
}
wait_for_usr1() {
    attempts=0
    while [ "$attempts" -lt 200 ]; do
        grep -q '^USR1$' "$KAP_SIGNAL_LOG" 2>/dev/null && return 0
        attempts=$((attempts + 1))
        sleep 0.02
    done
    return 1
}

sh "$PROJECT_ROOT/scripts/launch.sh" & wrapper1=$!
first=$(wait_for_pidfile) || { echo "first launcher did not publish a live PID" >&2; exit 1; }
[ "$(readlink "/proc/$first/exe" 2>/dev/null || true)" = "$(readlink -f "$KAP_APP_BIN")" ]
sh "$PROJECT_ROOT/scripts/launch.sh"
wait_for_usr1 || { echo "second launch did not raise existing instance" >&2; exit 1; }
[ "$(cat "$KAP_PID_FILE")" = "$first" ]
kill -TERM "$first"
wait "$wrapper1"
wrapper1=
first=

sleep 30 & unrelated=$!
printf '%s\n' "$unrelated" >"$KAP_PID_FILE"
sh "$PROJECT_ROOT/scripts/launch.sh" & wrapper2=$!
second=$(wait_for_pidfile) || { echo "launcher did not replace foreign PID" >&2; exit 1; }
[ "$second" != "$unrelated" ]
kill -0 "$unrelated"
[ "$(readlink "/proc/$second/exe" 2>/dev/null || true)" = "$(readlink -f "$KAP_APP_BIN")" ]
kill -TERM "$second"
wait "$wrapper2"
wrapper2=
second=
kill -TERM "$unrelated"
wait "$unrelated" 2>/dev/null || true
unrelated=
printf 'test-launcher-integration: ok\n'
