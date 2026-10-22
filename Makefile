# ─────────────────────────────────────────────────────────────────────────────
# Music Player — local development shortcuts
# Mirrors the commands used by CI; run `make help` for the list.
# ─────────────────────────────────────────────────────────────────────────────
SHELL := /bin/bash
FLUTTER ?= flutter
DART ?= dart

.DEFAULT_GOAL := help

.PHONY: help setup format format-check analyze test test-file test-native test-kotlin test-all check coverage build-web serve build-apk clean

help: ## Show available targets
	@printf 'Usage: make <target>\n\n'
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## Resolve Flutter and native-runtime dependencies
	$(FLUTTER) pub get
	cd native_audio_runtime && $(DART) pub get

format: ## Format Dart code (app + native runtime)
	$(DART) format lib test native_audio_runtime/lib native_audio_runtime/test

format-check: ## Fail if any Dart file is not formatted
	$(DART) format --output=none --set-exit-if-changed lib test native_audio_runtime/lib native_audio_runtime/test

analyze: ## Run the Dart/Flutter analyzer (CI parity)
	$(FLUTTER) analyze --no-pub

test: ## Run all Flutter unit/widget/golden tests
	$(FLUTTER) test --no-pub

test-file: ## Run one test file: make test-file FILE=test/foo_test.dart
	@test -n "$(FILE)" || { echo "Usage: make test-file FILE=test/foo_test.dart"; exit 1; }
	$(FLUTTER) test --no-pub $(FILE)

test-native: ## Run native_audio_runtime C/FFI tests
	cd native_audio_runtime && $(DART) test

test-kotlin: ## Run Android Kotlin unit tests via Gradle
	cd android && ./gradlew :app:testDebugUnitTest --no-daemon

test-all: analyze test test-native test-kotlin ## Analyze + Flutter/native/Kotlin tests
	@echo "All checks passed."

check: test-all ## Alias for test-all

coverage: ## Run Flutter tests with coverage and build an HTML report
	$(FLUTTER) test --no-pub --coverage
	genhtml coverage/lcov.info -o coverage/html
	@echo "Coverage report: coverage/html/index.html"

build-web: ## Build the release web app consumed by server.js
	$(FLUTTER) build web --release --no-pub

serve: build-web ## Build web then serve it on http://localhost:5000
	node server.js

build-apk: ## Build a debug APK (release needs signing secrets)
	$(FLUTTER) build apk --debug

clean: ## Remove build outputs and coverage reports
	$(FLUTTER) clean
	rm -rf coverage
