# Interview Helper — common tasks (macOS + Node)
# Run `make` or `make help` for targets.

.DEFAULT_GOAL := help

NPM     ?= npm
NODE    ?= node
SWIFT   ?= swift
SWIFT_PKG := macos-native
APP_NAME := InterviewHelperMac

.PHONY: all help install test start dev mac-native mac-app mac-app-debug mac-icon swift-build package-mac clean distclean env

# Local setup + builds: env file, deps, Swift debug build (does not launch the GUI app).
all: env install swift-build
	@echo "make all: done — run \`make test\` for tests. To run the real .app (Screen Recording goes to InterviewHelperMac, not Cursor): \`make mac-app-debug\`."

help:
	@echo "Interview Helper — Makefile targets"
	@echo ""
	@echo "  make all           env + install + swift-build"
	@echo "  make install       Install Node dependencies (npm install)"
	@echo "  make env           Copy .env.example to .env if .env is missing"
	@echo "  make test          Run Node API tests"
	@echo "  make start         Run backend server (foreground)"
	@echo "  make dev           Run backend with nodemon reload"
	@echo "  make mac-native    swift run (fast; Screen Recording may attach to Cursor/Terminal — avoid if you want app-only permission)"
	@echo "  make mac-app       Release .app + open (InterviewHelperMac in Privacy settings)"
	@echo "  make mac-app-debug Debug .app + open (same; use Run and Debug in Cursor + CodeLLDB to debug that binary)"
	@echo "  make swift-build   Debug-build the Swift package"
	@echo "  make mac-icon      Rebuild AppIcon.icns from macos-native/Resources/AppIcon-1024.png"
	@echo "  make package-mac   Release-build + dist/$(APP_NAME).app"
	@echo "  make clean         Remove dist/ and Swift .build/"
	@echo "  make distclean     clean + remove node_modules/"
	@echo ""

install:
	$(NPM) install

env:
	@test -f .env || cp .env.example .env
	@echo ".env ready (edit OPENAI_API_KEY and VIEWER_TOKEN)"

test:
	$(NPM) test

start:
	$(NPM) start

dev:
	$(NPM) run dev

mac-native:
	$(NPM) run mac:native

mac-app:
	bash scripts/assemble-mac-app.sh release
	open "$(CURDIR)/dist/$(APP_NAME).app"

mac-app-debug:
	bash scripts/assemble-mac-app.sh debug
	open "$(CURDIR)/dist/$(APP_NAME).app"

mac-icon:
	bash scripts/build-mac-icon.sh "$(CURDIR)/macos-native/Resources/AppIcon.icns"

swift-build:
	$(SWIFT) build --package-path $(SWIFT_PKG)

package-mac:
	$(NPM) run package:mac

clean:
	rm -rf dist "$(SWIFT_PKG)/.build"

distclean: clean
	rm -rf node_modules
