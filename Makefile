.DEFAULT_GOAL := help
.PHONY: help build run test clean release verify-sign hooks

SCHEME    := Burrow
APP_NAME  := Burrow.app
BUILD_DIR := build
DEBUG_APP := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)

# Positional args: anything on the make command line that isn't a known
# target. Used to support `make release 0.1.2`. The catch-all `%:` rule at
# the bottom turns those args into no-op goals so make doesn't error on
# them. Note: $@ at top-level expands to empty — must compute the filter
# inside the recipe.
KNOWN_TARGETS := help build run test clean release verify-sign hooks
ARGS = $(filter-out $(KNOWN_TARGETS),$(MAKECMDGOALS))

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  make %-11s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

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

release: ## Full release pipeline (prompts for version): sign + notarize + GitHub + appcast
	@VERSION="$(ARGS)"; \
	if [ -z "$$VERSION" ]; then \
		CURRENT=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Burrow/Info.plist); \
		printf "Version to release (current %s): " "$$CURRENT"; \
		read VERSION < /dev/tty; \
	fi; \
	test -n "$$VERSION" || (echo "version required"; exit 1); \
	scripts/release.sh "$$VERSION"

verify-sign: ## Archive Release and verify Developer ID signature (no notarization)
	xcodebuild -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' \
		-archivePath /tmp/Burrow.xcarchive archive
	codesign --verify --deep --strict --verbose=2 \
		/tmp/Burrow.xcarchive/Products/Applications/$(APP_NAME)

clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR)

hooks: ## Install git commit-msg hook
	git config core.hooksPath .githooks
	@echo "core.hooksPath set to .githooks"

# Catch-all so positional args (e.g. the `0.1.2` in `make release 0.1.2`)
# don't trigger "no rule to make target" errors. Does nothing.
%:
	@:
