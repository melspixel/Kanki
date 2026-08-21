PROJECT_ROOT := $(CURDIR)
PYTHON ?= python3
BASH ?= bash
CC ?= cc
BUILD ?= build
ANKI ?=
CARGO_HOME ?=
PROTOC ?=
TOOLCHAIN_BIN ?=
QEMU_ARM ?= qemu-arm-static
ROOTFS ?=
ARMHF ?= $(PROJECT_ROOT)/$(BUILD)/armhf
VERSION ?= 0.1.0-dev
BUILD_COMMIT ?= $(shell git -C "$(PROJECT_ROOT)" rev-parse HEAD 2>/dev/null || printf unknown)

.PHONY: static-test host-c-test host-backend armhf qemu-host-sanity qemu-smoke package test clean

static-test:
	KAP_BUILD_DIR="$(PROJECT_ROOT)/$(BUILD)/static-gates" sh ./testenv/scripts/run-static-gates.sh

host-c-test:
	mkdir -p "$(BUILD)/host"
	$(CC) -O2 -std=c99 -Wall -Wextra -Werror -Icore native/app.c -ldl -o "$(BUILD)/host/kap-app"
	$(CC) -O2 -std=c99 -Wall -Wextra -Werror native/audio.c -ldl -o "$(BUILD)/host/kap-audio"
	$(CC) -O2 -std=c99 -Wall -Wextra -Werror -Icore native/sync.c -ldl -o "$(BUILD)/host/kap-sync"
	"$(BUILD)/host/kap-audio" --self-test
	"$(BUILD)/host/kap-sync" --self-test

host-backend:
	@test -n "$(ANKI)" || { echo "ANKI=<exact pinned Anki checkout> is required" >&2; exit 64; }
	@test -n "$(CARGO_HOME)" || { echo "CARGO_HOME=<prepared offline cargo cache> is required" >&2; exit 64; }
	@test -n "$(PROTOC)" || { echo "PROTOC=<pinned protoc executable> is required" >&2; exit 64; }
	PROJECT="$(PROJECT_ROOT)" ANKI="$(ANKI)" CARGO_HOME="$(CARGO_HOME)" PROTOC="$(PROTOC)" \
		$(BASH) ./testenv/scripts/run-host-backend-gates.sh

armhf:
	@test -n "$(ANKI)" || { echo "ANKI=<exact pinned Anki checkout> is required" >&2; exit 64; }
	@test -n "$(CARGO_HOME)" || { echo "CARGO_HOME=<prepared offline cargo cache> is required" >&2; exit 64; }
	@test -n "$(PROTOC)" || { echo "PROTOC=<pinned protoc executable> is required" >&2; exit 64; }
	@test -n "$(TOOLCHAIN_BIN)" || { echo "TOOLCHAIN_BIN=<KindleHF bin directory> is required" >&2; exit 64; }
	PROJECT="$(PROJECT_ROOT)" ANKI="$(ANKI)" CARGO_HOME="$(CARGO_HOME)" PROTOC="$(PROTOC)" \
		TOOLCHAIN_BIN="$(TOOLCHAIN_BIN)" OUT="$(ARMHF)" BUILD_COMMIT="$(BUILD_COMMIT)" \
		$(BASH) ./testenv/scripts/run-armhf-gates.sh

qemu-host-sanity:
	@test -n "$(TOOLCHAIN_BIN)" || { echo "TOOLCHAIN_BIN=<KindleHF bin directory> is required" >&2; exit 64; }
	PROJECT="$(PROJECT_ROOT)" OUT="$(PROJECT_ROOT)/$(BUILD)/qemu-host-sanity" \
		TOOLCHAIN_BIN="$(TOOLCHAIN_BIN)" QEMU_ARM="$(QEMU_ARM)" \
		$(BASH) ./testenv/scripts/run-qemu-host-sanity.sh

qemu-smoke:
	@test -d "$(ARMHF)" || { echo "ARMHF=<run-armhf-gates output directory> is required" >&2; exit 64; }
	@test -n "$(ROOTFS)" || { echo "ROOTFS=<checksum-verified PW6 rootfs> is required" >&2; exit 64; }
	@test -n "$(TOOLCHAIN_BIN)" || { echo "TOOLCHAIN_BIN=<KindleHF bin directory> is required" >&2; exit 64; }
	PROJECT="$(PROJECT_ROOT)" ARMHF="$(ARMHF)" ROOTFS="$(ROOTFS)" \
		TOOLCHAIN_BIN="$(TOOLCHAIN_BIN)" QEMU_ARM="$(QEMU_ARM)" \
		$(BASH) ./testenv/scripts/run-qemu-smoke.sh

package:
	@test -d "$(ARMHF)" || { echo "ARMHF=<run-armhf-gates output directory> is required" >&2; exit 64; }
	PROJECT="$(PROJECT_ROOT)" ARMHF="$(ARMHF)" VERSION="$(VERSION)" BUILD_COMMIT="$(BUILD_COMMIT)" \
		$(BASH) ./testenv/scripts/package-and-audit.sh

test: static-test

clean:
	rm -rf "$(BUILD)" tools/__pycache__ tests/__pycache__
