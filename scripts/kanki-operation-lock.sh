#!/bin/sh

# This file is sourced only after the package verifier has authenticated the
# install tree.  The lock file itself is manifest-owned and must never be
# unlinked while a process may hold it: Linux flock ownership follows the open
# file description inherited by the collection worker.

KANKI_OPERATION_LOCK_HELD=0
KANKI_OPERATION_LOCK_MODE=
KANKI_OPERATION_LOCK_LOCAL_OWNER=

kanki_operation_lock_paths_are_safe() {
    [ -n "${KANKI_OPERATION_ROOT:-}" ] &&
        [ "$KANKI_OPERATION_ROOT" != / ] &&
        [ "${KANKI_OPERATION_LOCK_FILE:-}" = \
            "$KANKI_OPERATION_ROOT/.kanki.operation.lock" ] &&
        [ "${KANKI_OPERATION_STATE_DIR:-}" = \
            "$KANKI_OPERATION_ROOT/.kanki.lock" ]
}

kanki_operation_lock_acquire() {
    KANKI_OPERATION_REQUESTED_MODE=$1
    case "$KANKI_OPERATION_REQUESTED_MODE" in
        launch|sync) ;;
        *) return 64 ;;
    esac
    kanki_operation_lock_paths_are_safe || return 70
    [ -x "${KANKI_FLOCK:-/usr/bin/flock}" ] || return 69
    [ -f "$KANKI_OPERATION_LOCK_FILE" ] &&
        [ ! -L "$KANKI_OPERATION_LOCK_FILE" ] || return 70

    if ! exec 9<>"$KANKI_OPERATION_LOCK_FILE"; then
        return 70
    fi
    if "${KANKI_FLOCK:-/usr/bin/flock}" -n -E 74 9; then
        :
    else
        KANKI_OPERATION_LOCK_STATUS=$?
        exec 9>&-
        return "$KANKI_OPERATION_LOCK_STATUS"
    fi

    # An exclusive kernel lock makes replacement of stale diagnostic metadata
    # safe. The metadata is not the lock and is never used to reclaim it.
    rm -rf "$KANKI_OPERATION_STATE_DIR"
    if ! mkdir "$KANKI_OPERATION_STATE_DIR"; then
        exec 9>&-
        return 70
    fi
    if ! printf '%s\n' "$$" >"$KANKI_OPERATION_STATE_DIR/pid" ||
        ! printf '%s\n' "$KANKI_OPERATION_REQUESTED_MODE" \
            >"$KANKI_OPERATION_STATE_DIR/mode"; then
        rm -f "$KANKI_OPERATION_STATE_DIR/pid" \
            "$KANKI_OPERATION_STATE_DIR/mode"
        rmdir "$KANKI_OPERATION_STATE_DIR" 2>/dev/null || true
        exec 9>&-
        return 70
    fi

    KANKI_OPERATION_LOCK_HELD=1
    KANKI_OPERATION_LOCK_MODE=$KANKI_OPERATION_REQUESTED_MODE
    KANKI_OPERATION_LOCK_LOCAL_OWNER=$$
}

kanki_operation_lock_validate_inherited() {
    KANKI_OPERATION_EXPECTED_OWNER=$1
    KANKI_OPERATION_EXPECTED_MODE=$2
    case "$KANKI_OPERATION_EXPECTED_OWNER" in
        ''|*[!0-9]*) return 74 ;;
    esac
    case "$KANKI_OPERATION_EXPECTED_MODE" in
        launch|sync) ;;
        *) return 74 ;;
    esac
    kanki_operation_lock_paths_are_safe || return 70
    [ -x "${KANKI_FLOCK:-/usr/bin/flock}" ] || return 69
    [ -f "$KANKI_OPERATION_LOCK_FILE" ] &&
        [ ! -L "$KANKI_OPERATION_LOCK_FILE" ] || return 70
    [ "$(cat "$KANKI_OPERATION_STATE_DIR/pid" 2>/dev/null || true)" = \
        "$KANKI_OPERATION_EXPECTED_OWNER" ] || return 74
    [ "$(cat "$KANKI_OPERATION_STATE_DIR/mode" 2>/dev/null || true)" = \
        "$KANKI_OPERATION_EXPECTED_MODE" ] || return 74

    # Linux/PW6 can additionally prove that descriptor 9 names the authenticated
    # manifest-owned lock file. Host contract runners without /proc still prove
    # the inherited open-file-description lock below.
    if [ -e "/proc/$$/fd/9" ]; then
        KANKI_OPERATION_FD_PATH=$(readlink -f "/proc/$$/fd/9" 2>/dev/null || true)
        KANKI_OPERATION_FILE_PATH=$(readlink -f \
            "$KANKI_OPERATION_LOCK_FILE" 2>/dev/null || true)
        [ -n "$KANKI_OPERATION_FD_PATH" ] &&
            [ "$KANKI_OPERATION_FD_PATH" = "$KANKI_OPERATION_FILE_PATH" ] ||
            return 74
    fi
    "${KANKI_FLOCK:-/usr/bin/flock}" -n -E 74 9 || return 74
}

kanki_operation_lock_cleanup() {
    if [ "${KANKI_OPERATION_LOCK_HELD:-0}" = 1 ]; then
        KANKI_OPERATION_CURRENT_OWNER=$(cat \
            "$KANKI_OPERATION_STATE_DIR/pid" 2>/dev/null || true)
        KANKI_OPERATION_CURRENT_MODE=$(cat \
            "$KANKI_OPERATION_STATE_DIR/mode" 2>/dev/null || true)
        if [ "$KANKI_OPERATION_CURRENT_OWNER" = \
                "$KANKI_OPERATION_LOCK_LOCAL_OWNER" ] &&
            [ "$KANKI_OPERATION_CURRENT_MODE" = \
                "$KANKI_OPERATION_LOCK_MODE" ]; then
            rm -f "$KANKI_OPERATION_STATE_DIR/pid" \
                "$KANKI_OPERATION_STATE_DIR/mode"
            rmdir "$KANKI_OPERATION_STATE_DIR" 2>/dev/null || true
        fi
        exec 9>&-
    fi
    KANKI_OPERATION_LOCK_HELD=0
    KANKI_OPERATION_LOCK_MODE=
    KANKI_OPERATION_LOCK_LOCAL_OWNER=
}
