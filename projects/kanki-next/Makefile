ROOT := $(CURDIR)
BUILD := $(ROOT)/build
CC ?= cc
CFLAGS ?= -O2 -std=c99 -Wall -Wextra -Werror
KINDLE_CC ?= arm-kindlehf-linux-gnueabihf-gcc

.PHONY: all assets test host-build armhf-probe upstream-audit clean

all: test

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/probe.png: | $(BUILD)
	python3 -c 'from PIL import Image, ImageDraw; p="$(BUILD)/probe.png"; im=Image.new("L",(640,360),255); d=ImageDraw.Draw(im); d.rectangle((18,18,621,341),outline=0,width=5); d.ellipse((72,72,272,272),outline=0,width=8); d.line((330,80,560,280),fill=0,width=10); d.line((560,80,330,280),fill=0,width=10); d.text((220,315),"KANKI NEXT IMAGE SCALE PROBE",fill=0); im.save(p)'

$(BUILD)/probe_asset.h: web/probe.html.in web/reviewer.css web/reviewer.js tools/build_probe_asset.py $(BUILD)/probe.png
	python3 tools/build_probe_asset.py --root $(ROOT) --image $(BUILD)/probe.png --output $@

assets: $(BUILD)/probe_asset.h

$(BUILD)/test_scale: src/kindle_webkit_scale.c tests/test_scale.c src/kindle_webkit_scale.h | $(BUILD)
	$(CC) $(CFLAGS) -Isrc src/kindle_webkit_scale.c tests/test_scale.c -o $@

$(BUILD)/render_probe-host: src/kindle_webkit_scale.c src/render_probe.c src/kindle_webkit_scale.h $(BUILD)/probe_asset.h
	$(CC) $(CFLAGS) -Isrc -I$(BUILD) src/kindle_webkit_scale.c src/render_probe.c -o $@ -ldl

host-build: $(BUILD)/render_probe-host

$(BUILD)/kanki-next-render-probe-armhf: src/kindle_webkit_scale.c src/render_probe.c src/kindle_webkit_scale.h $(BUILD)/probe_asset.h
	$(KINDLE_CC) $(CFLAGS) -Isrc -I$(BUILD) src/kindle_webkit_scale.c src/render_probe.c -o $@ -ldl

armhf-probe: $(BUILD)/kanki-next-render-probe-armhf

upstream-audit:
	@test -n "$(RANKI_SOURCE)" || (echo 'RANKI_SOURCE is required' >&2; exit 2)
	@test -n "$(RANKI_PACKAGE)" || (echo 'RANKI_PACKAGE is required' >&2; exit 2)
	python3 tools/audit_ranki.py \
		--source "$(RANKI_SOURCE)" \
		--package "$(RANKI_PACKAGE)" \
		--lock upstream.lock \
		--output $(BUILD)/ranki-audit.json

test: assets $(BUILD)/test_scale $(BUILD)/render_probe-host
	$(BUILD)/test_scale
	python3 tests/test_probe_contract.py --root $(ROOT) --header $(BUILD)/probe_asset.h
	python3 tests/test_audit_ranki.py
	python3 -m py_compile tools/build_probe_asset.py tools/audit_ranki.py tests/test_probe_contract.py tests/test_audit_ranki.py
	node --check web/reviewer.js
	sh -n scripts/launch-probe.sh
	sh -n scripts/collect-device-report.sh
	sh -n scripts/package-probe.sh
	python3 -m json.tool package/menu.json >/dev/null

clean:
	rm -rf $(BUILD)
