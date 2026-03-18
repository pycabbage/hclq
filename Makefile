# Version from git tag, description, or commit hash
VERSION = $(shell ver=$$(git tag -l --points-at HEAD) && [ -z $$ver ] && ver=$$(git describe --always --dirty); printf $$ver)
LDFLAGS = -s -w -X github.com/pycabbage/hclq/cmd.version=$(VERSION)
DIST    = dist

.PHONY: build clean install test default

default: build test

build: $(DIST)/hclq

$(DIST)/hclq:
	@mkdir -p $(DIST)
	go build -ldflags="$(LDFLAGS)" -o $(DIST)/hclq .

clean:
	rm -rf $(DIST)

install:
	go install -ldflags="$(LDFLAGS)" .

test: build
	@mkdir -p test
	HCLQ_BIN=$(CURDIR)/$(DIST)/hclq go test -v ./...
