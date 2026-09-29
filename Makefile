CC ?= cc
CFLAGS ?= -O2 -pipe
QSB ?= /usr/lib/qt6/bin/qsb

NATIVE = bin/hotbar-native bin/hotbar-places-native
SHADERS = components/shaders/flame.frag.qsb

.PHONY: native shaders clean test bench

# Optional fast path: a C client for the CLI and a C Places helper. Only a C
# compiler and libc are needed. bin/hotbar and the widget fall back to the
# shell implementations when these are absent.
native: $(NATIVE)

bin/hotbar-native: bin/hotbar-client.c
	$(CC) $(CFLAGS) -std=c11 -Wall -Wextra -o $@ $<

bin/hotbar-places-native: bin/hotbar-places.c
	$(CC) $(CFLAGS) -std=c11 -Wall -Wextra -o $@ $<

# The flame shader ships precompiled (Qt 6 loads .qsb only). Rebuild after
# editing the .frag source; needs qt6-shadertools.
shaders: $(SHADERS)

components/shaders/%.frag.qsb: components/shaders/%.frag
	$(QSB) --glsl "100 es,120,150" --hlsl 50 --msl 12 -o $@ $<

test:
	tests/run.sh

bench: native
	python3 tests/bench_native.py

clean:
	rm -f $(NATIVE)
