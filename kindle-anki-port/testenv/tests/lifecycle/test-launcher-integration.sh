#!/bin/sh
set -eu
PROJECT_ROOT=${PROJECT_ROOT:?}
TMP=$(mktemp -d)
trap 'set +e; [ -f "$TMP/ext/run/kap-app.pid" ] && kill "$(cat "$TMP/ext/run/kap-app.pid")" 2>/dev/null; [ -n "${unrelated:-}" ] && kill "$unrelated" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/ext" "$TMP/data"
cat > "$TMP/ext/kap-app" <<'APP'
#!/bin/sh
trap 'echo USR1 >> "$KAP_SIGNAL_LOG"' USR1
trap 'exit 0' TERM INT HUP
echo START >> "$KAP_SIGNAL_LOG"
while :; do sleep 1; done
APP
chmod +x "$TMP/ext/kap-app"
printf '{"build":"test"}\n' > "$TMP/ext/BUILD.json"
printf '[General]\n' > "$TMP/ext/config.example.ini"
export KAP_EXT="$TMP/ext" KAP_DATA="$TMP/data" KAP_RUN="$TMP/ext/run" KAP_LOGDIR="$TMP/ext/logs"
export KAP_APP="$TMP/ext/kap-app" KAP_SIGNAL_LOG="$TMP/signals" KAP_FOREGROUND=0
"$PROJECT_ROOT/scripts/launch.sh"
sleep 1
first=$(cat "$TMP/ext/run/kap-app.pid")
kill -0 "$first"
"$PROJECT_ROOT/scripts/launch.sh"
sleep 1
grep -q USR1 "$TMP/signals"
[ "$(cat "$TMP/ext/run/kap-app.pid")" = "$first" ]
kill "$first"
wait "$first" 2>/dev/null || true
sleep 1
sleep 30 & unrelated=$!
printf '%s\n' "$unrelated" > "$TMP/ext/run/kap-app.pid"
"$PROJECT_ROOT/scripts/launch.sh"
sleep 1
kill -0 "$unrelated"
second=$(cat "$TMP/ext/run/kap-app.pid")
[ "$second" != "$unrelated" ]
kill "$second" 2>/dev/null || true
kill "$unrelated" 2>/dev/null || true
wait "$unrelated" 2>/dev/null || true
unset unrelated
