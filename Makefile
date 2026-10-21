# SwiftDefaults — build interface.
#
# `make` prints the list of targets. Every target is phony.

SHELL := /bin/bash

APP_NAME := SwiftDefaults
SRC_DIR  := $(APP_NAME)
APP_BUNDLE := $(APP_NAME).app
APP_BUNDLE_DEBUG := $(APP_NAME)-Debug.app
ICON := $(SRC_DIR)/Resources/AppIcon.icns
ENTITLEMENTS := $(SRC_DIR)/$(APP_NAME).entitlements
# SwiftPM generates this; Bundle.module fatalErrors without it, so the .app must ship it.
RESOURCE_BUNDLE := $(APP_NAME)_$(SRC_DIR).bundle
SPM_DIR := .build
SPM_DEBUG_DIR := $(SPM_DIR)/debug
SPM_RELEASE_DIR := $(SPM_DIR)/release
# The release artifacts land here: the disk image and the checksum file next to it.
RELEASE_DIR := release
DMG_STAGE := $(SPM_DIR)/dmg-stage

# The version comes from the command line: `make release VERSION=1.2.3`.
# It never comes from a file in the repository.
VERSION ?=

# The build number is the version without its dots and letters: 1.2.3 gives 123.
BUILD_NUMBER := $(shell printf '%s' '$(VERSION)' | tr -cd '0-9')

# The name of the disk image. The tap matches the asset by name, so it never changes.
DMG_NAME := $(APP_NAME)-$(VERSION).dmg

.PHONY: help build test run app app-bundle-debug run-bundle-debug \
	dmg release-artifacts release clean _require_version

.DEFAULT_GOAL := help

## help — list every target

help:
	@printf '%s\n' \
		'SwiftDefaults — build targets.' \
		'' \
		'  help                 List every target (default).' \
		'  build                Build the SwiftPM package.' \
		'  test                 Run the SwiftPM test suite.' \
		'  run                  Build and run the app from the command line.' \
		'  app                  Build the shipping bundle into SwiftDefaults.app and sign it ad-hoc.' \
		'  app-bundle-debug     Build the debug bundle into SwiftDefaults-Debug.app.' \
		'  run-bundle-debug     Build the debug bundle and open it.' \
		'  dmg                  Build the disk image release/SwiftDefaults-<version>.dmg.' \
		'  release-artifacts    Build the DMG and write its checksum file for the Homebrew tap.' \
		'  release VERSION=x.y.z  Build the artifacts, tag v<x.y.z> locally, print the push command.' \
		'  clean                Remove the build output.' \
		'' \
		'Notes' \
		'  The app bundle is assembled by hand from the SwiftPM build. `swift build` alone' \
		'  gives a bare executable without the resources the app needs.' \
		'  SwiftDefaults is Apple silicon only (arm64), so there is no per-architecture target.' \
		'  The tweak registry ships in Contents/Resources, where the app reads it. The bundle' \
		'  holds nothing in the app root, because codesign seals only what lives in Contents/.' \
		'  Signing stays ad-hoc: codesign --force --sign - --options runtime. There is no' \
		'  Developer ID identity and no notarization.' \
		'  `make release VERSION=1.2.3` builds the artifacts, creates the tag v1.2.3 locally and' \
		'  prints the command that pushes the commit and the tag. It never pushes by itself.'

## build — build the package

build:
	swift build

## test — run the test suite

test:
	swift test

## run — build and run the app

run:
	swift run

## app — the bundle the product ships

app:
	swift build -c release
	$(call assemble_bundle,$(SPM_RELEASE_DIR)/$(APP_NAME),$(APP_BUNDLE))
	@if [ -n "$(strip $(VERSION))" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(APP_BUNDLE)/Contents/Info.plist"; \
	fi
	codesign --force --sign - --options runtime "$(APP_BUNDLE)"
	codesign --verify --deep --strict "$(APP_BUNDLE)"
	@echo "Built and signed $(APP_BUNDLE)"

## app-bundle-debug — the bundle for development

app-bundle-debug:
	swift build
	$(call assemble_bundle,$(SPM_DEBUG_DIR)/$(APP_NAME),$(APP_BUNDLE_DEBUG))
	@echo "Built $(APP_BUNDLE_DEBUG)"

## run-bundle-debug — build the debug bundle and open it

run-bundle-debug: app-bundle-debug
	open "$(APP_BUNDLE_DEBUG)"

## dmg — the disk image the tap installs

dmg: _require_version app
	@rm -rf "$(DMG_STAGE)"
	@mkdir -p "$(DMG_STAGE)" "$(RELEASE_DIR)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGE)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_STAGE)/Applications"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGE)" -ov -format UDZO "$(RELEASE_DIR)/$(DMG_NAME)"
	@rm -rf "$(DMG_STAGE)"
	@echo "Built $(RELEASE_DIR)/$(DMG_NAME)"

## release-artifacts — the DMG and the checksum file the tap expects

release-artifacts: dmg
	@cd "$(RELEASE_DIR)" && shasum -a 256 "$(DMG_NAME)" > "$(DMG_NAME).sha256"
	@echo "$(RELEASE_DIR)/$(DMG_NAME).sha256:"
	@cat "$(RELEASE_DIR)/$(DMG_NAME).sha256"

## release — build the artifacts and tag them, without pushing

release: _require_version
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "error: the working tree is dirty. Commit or stash your changes first."; \
		git status --short; \
		exit 1; \
	fi
	@if git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null; then \
		echo "error: the tag v$(VERSION) already exists."; \
		exit 1; \
	fi
	$(MAKE) release-artifacts VERSION=$(VERSION)
	git tag -a "v$(VERSION)" -m "$(APP_NAME) $(VERSION)"
	@echo ""
	@echo "Tagged v$(VERSION). Push the commit and the tag with:"
	@echo "  git push origin main --tags"

## clean — remove everything the build produces

clean:
	rm -rf "$(SPM_DIR)" "$(APP_BUNDLE)" "$(APP_BUNDLE_DEBUG)" "$(RELEASE_DIR)"
	@echo "Removed $(SPM_DIR)/, $(APP_BUNDLE)/, $(APP_BUNDLE_DEBUG)/ and $(RELEASE_DIR)/."

# The name of a release artifact carries the version, so the version must be there.
_require_version:
	@if [ -z "$(strip $(VERSION))" ]; then \
		echo "error: $(MAKECMDGOALS) needs a version, for example: make $(MAKECMDGOALS) VERSION=1.2.3"; \
		exit 1; \
	fi

# $(1) path of the binary, $(2) path of the bundle
define assemble_bundle
	rm -rf "$(2)"
	mkdir -p "$(2)/Contents/MacOS" "$(2)/Contents/Resources"
	cp "$(1)" "$(2)/Contents/MacOS/$(APP_NAME)"
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
		-e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.wigglysheets.$(APP_NAME)/g' \
		-e 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' \
		"$(SRC_DIR)/Info.plist" > "$(2)/Contents/Info.plist"
	mkdir -p "$(2)/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Resources"
	cp "$(SRC_DIR)/Resources/tweaks.json" "$(2)/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Resources/tweaks.json"
	cp "$(ICON)" "$(2)/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Resources/AppIcon.icns"
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict>' \
		'<key>CFBundleIdentifier</key><string>com.wigglysheets.$(APP_NAME).resources</string>' \
		'<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>' \
		'<key>CFBundleName</key><string>$(RESOURCE_BUNDLE)</string>' \
		'<key>CFBundlePackageType</key><string>BNDL</string>' \
		'</dict></plist>' > "$(2)/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Info.plist"
	cp "$(ICON)" "$(2)/Contents/Resources/"
	if [ -f "$(ENTITLEMENTS)" ]; then cp "$(ENTITLEMENTS)" "$(2)/Contents/Resources/"; fi
endef
