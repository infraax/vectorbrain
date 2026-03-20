# VectorBrain Go Package — Build targets
# GOMODCACHE is local to avoid conflicts with root-owned dirs from WirePod sudo builds.
GOMODCACHE ?= $(PWD)/.gomodcache
GOFLAGS    := GOMODCACHE=$(GOMODCACHE)

.PHONY: build run test tidy clean lint

build:
	$(GOFLAGS) go build -o bin/vectorbrain ./cmd/vectorbrain/

run: build
	VB_LOG_DEV=true ./bin/vectorbrain --config configs/default.json

test:
	$(GOFLAGS) go test ./...

tidy:
	GONOSUMDB="*" $(GOFLAGS) go mod tidy

clean:
	rm -rf bin/

lint:
	$(GOFLAGS) golangci-lint run
