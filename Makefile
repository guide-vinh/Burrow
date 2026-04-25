.DEFAULT_GOAL := help
.PHONY: help build run test clean release hooks

SCHEME    := Burrow
APP_NAME  := Burrow.app
BUILD_DIR := build
DEBUG_APP := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  make %-9s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build Debug
	xcodebuild -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' \
		-derivedDataPath $(BUILD_DIR) build

run: build ## Build Debug and launch the app
	open $(DEBUG_APP)

test: ## Run unit tests
	xcodebuild -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' \
		-derivedDataPath $(BUILD_DIR) test

release: ## Build Release (universal)
	xcodebuild -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' \
		-derivedDataPath $(BUILD_DIR) build

clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR)

hooks: ## Install git commit-msg hook
	git config core.hooksPath .githooks
	@echo "core.hooksPath set to .githooks"
