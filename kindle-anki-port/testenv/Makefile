SHELL := /bin/bash
PROJECT_ROOT ?= $(abspath ..)
ANKI_ROOT ?=
PACKAGE ?=

.PHONY: host armhf package lifecycle all
all: host lifecycle
host:
	PROJECT_ROOT="$(PROJECT_ROOT)" ANKI_ROOT="$(ANKI_ROOT)" scripts/run-host-gates.sh
armhf:
	PROJECT_ROOT="$(PROJECT_ROOT)" ANKI_ROOT="$(ANKI_ROOT)" scripts/run-armhf-gates.sh
package:
	python3 scripts/package_audit.py --package "$(PACKAGE)"
lifecycle:
	PROJECT_ROOT="$(PROJECT_ROOT)" tests/lifecycle/test-launcher.sh
