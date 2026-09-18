SHELL := /usr/bin/env bash

.PHONY: build validate clean

build:
	./scripts/build.sh

validate:
	./scripts/validate-sources.py rules

clean:
	rm -rf dist .cache .tmp
