PROJECT_ROOT := $(CURDIR)
PYTHON ?= python3
CC ?= cc
BUILD ?= build

.PHONY: static-test host-c-test test clean

static-test:
	KAP_BUILD_DIR="$(PROJECT_ROOT)/$(BUILD)/static-gates" ./testenv/scripts/run-static-gates.sh

host-c-test:
	mkdir -p "$(BUILD)/host"
	$(CC) -O2 -std=c99 -Wall -Wextra -Werror -Icore native/app.c -ldl -o "$(BUILD)/host/kap-app"
	$(CC) -O2 -std=c99 -Wall -Wextra -Werror native/audio.c -ldl -o "$(BUILD)/host/kap-audio"
	$(CC) -O2 -std=c99 -Wall -Wextra -Werror -Icore native/sync.c -ldl -o "$(BUILD)/host/kap-sync"
	"$(BUILD)/host/kap-audio" --self-test
	"$(BUILD)/host/kap-sync" --self-test

test: static-test

clean:
	rm -rf "$(BUILD)" tools/__pycache__ tests/__pycache__
