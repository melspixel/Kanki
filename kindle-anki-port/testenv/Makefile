SHELL := /bin/bash
PROJECT_ROOT ?= $(abspath ..)
ANKI_ROOT ?=
CARGO_HOME ?=
PROTOC ?=
TOOLCHAIN_BIN ?=
PACKAGE ?=
ROOTFS ?=
ROOTFS_IMAGE ?=
QEMU_ARM ?= qemu-arm-static

.PHONY: static host armhf package lifecycle qemu-host-sanity qemu-smoke all
all: static

static:
	$(MAKE) -C "$(PROJECT_ROOT)" static-test

host:
	@test -n "$(ANKI_ROOT)" || { echo "ANKI_ROOT=<exact pinned Anki checkout> is required" >&2; exit 64; }
	$(MAKE) -C "$(PROJECT_ROOT)" host-backend \
		ANKI="$(ANKI_ROOT)" CARGO_HOME="$(CARGO_HOME)" PROTOC="$(PROTOC)"

armhf:
	@test -n "$(ANKI_ROOT)" || { echo "ANKI_ROOT=<exact pinned Anki checkout> is required" >&2; exit 64; }
	$(MAKE) -C "$(PROJECT_ROOT)" armhf \
		ANKI="$(ANKI_ROOT)" CARGO_HOME="$(CARGO_HOME)" PROTOC="$(PROTOC)" \
		TOOLCHAIN_BIN="$(TOOLCHAIN_BIN)"

package:
	@test -n "$(PACKAGE)" || { echo "PACKAGE=<installation zip> is required" >&2; exit 64; }
	python3 scripts/package_audit.py --package "$(PACKAGE)"

lifecycle:
	sh "$(PROJECT_ROOT)/tests/test_lifecycle.sh"
	sh "$(PROJECT_ROOT)/tests/test_sync_wrapper_signal.sh"
	sh "$(PROJECT_ROOT)/tests/test_zombie_operation_lock.sh"

qemu-host-sanity:
	$(MAKE) -C "$(PROJECT_ROOT)" qemu-host-sanity \
		TOOLCHAIN_BIN="$(TOOLCHAIN_BIN)" QEMU_ARM="$(QEMU_ARM)"

qemu-smoke:
	$(MAKE) -C "$(PROJECT_ROOT)" qemu-smoke \
		TOOLCHAIN_BIN="$(TOOLCHAIN_BIN)" QEMU_ARM="$(QEMU_ARM)" \
		ROOTFS="$(ROOTFS)" ROOTFS_IMAGE="$(ROOTFS_IMAGE)"
