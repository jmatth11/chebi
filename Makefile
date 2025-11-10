zig ?= zig

.PHONY: all
all:
	zig build -Doptimize=ReleaseFast

.PHONY: t
t:
	zig build test

.PHONY: lt
lt:
	zig build -Doptimize=ReleaseFast -Dloadtest
	./loadtest.sh

.PHONY: clean
clean:
	rm -rf .zig-cache
	rm -rf zig-out

