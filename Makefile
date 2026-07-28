SHELL := bash

NVIM ?= nvim
NOTMUCH ?= notmuch
TEST_INIT ?= tests/test-init.lua
TEST_RUNNER ?= tests/run.lua

.PHONY: help deps lint format setup test clean check

help:
	@printf '%s\n' \
		'notmuch.nvim development targets:' \
		'  make deps       Check required local test dependencies' \
		'  make lint       Check Lua formatting with StyLua' \
		'  make format     Format Lua files with StyLua' \
		'  make setup      Recreate the disposable notmuch test database' \
		'  make test       Recreate test database and run the full test suite' \
		'  make clean      Remove generated test state' \
		'  make check      Alias for test, suitable for CI'

deps:
	@command -v "$(NVIM)" >/dev/null || { echo 'Missing dependency: $(NVIM)'; exit 1; }
	@command -v "$(NOTMUCH)" >/dev/null || { echo 'Missing dependency: $(NOTMUCH)'; exit 1; }
	@"$(NVIM)" --headless --clean +'lua local v=vim.version(); if v.major == 0 and v.minor < 10 then error("Neovim >= 0.10 required") end' +qa
	@"$(NOTMUCH)" --version >/dev/null

lint:
	@command -v stylua >/dev/null || { echo 'Missing dependency: stylua'; exit 1; }
	@stylua --check lua ftplugin tests

format:
	@command -v stylua >/dev/null || { echo 'Missing dependency: stylua'; exit 1; }
	@stylua lua ftplugin tests

setup: deps
	@tests/scripts/setup-notmuch-db.sh

test: setup
	@"$(NVIM)" --headless -u "$(TEST_INIT)" -l "$(TEST_RUNNER)"

clean:
	@tests/scripts/clean.sh

check: test
