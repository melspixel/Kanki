#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=${PROJECT_ROOT:?set PROJECT_ROOT to kindle-anki-port source root}
ANKI_ROOT=${ANKI_ROOT:?set ANKI_ROOT to the exact pinned official Anki checkout}
CARGO_HOME=${CARGO_HOME:?set CARGO_HOME to the prepared offline cache}
PROTOC=${PROTOC:?set PROTOC to the pinned protoc executable}

# Compatibility entry point. Keep one source of truth for both static and
# official-backend gates instead of duplicating a weaker subset here.
KAP_BUILD_DIR=${KAP_BUILD_DIR:-$PROJECT_ROOT/build/static-gates} \
  sh "$PROJECT_ROOT/testenv/scripts/run-static-gates.sh"
PROJECT="$PROJECT_ROOT" ANKI="$ANKI_ROOT" CARGO_HOME="$CARGO_HOME" PROTOC="$PROTOC" \
  bash "$PROJECT_ROOT/testenv/scripts/run-host-backend-gates.sh"
