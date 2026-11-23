# SwiftDefaults — build interface.
#
# `make` prints the list of targets. Every target is phony.

SHELL := /bin/bash

APP_NAME := SwiftDefaults
SRC_DIR  := $(APP_NAME)
# The release ships one bundle per architecture. Each build keeps a scratch
# directory of its own, because SwiftPM writes every architecture to one output
# path otherwise, and the last build would win.
SPM_DIR := .build
SPM_ARM_DIR := $(SPM_DIR)/arm64
SPM_INTEL_DIR := $(SPM_DIR)/x86_64
APP_BUNDLE_ARM64 := $(APP_NAME)-arm64.app
APP_BUNDLE_X86_64 := $(APP_NAME)-x86_64.app
APP_BUNDLES := $(APP_BUNDLE_ARM64) $(APP_BUNDLE_X86_64)
APP_BUNDLE_DEBUG := $(APP_NAME)-Debug.app
INSTALL_DIR ?= $(HOME)/Applications
INSTALL_APP := $(INSTALL_DIR)/$(APP_NAME).app
ICON := $(SRC_DIR)/Resources/AppIcon.icns
ENTITLEMENTS := $(SRC_DIR)/$(APP_NAME).entitlements
# SwiftPM generates this; Bundle.module fatalErrors without it, so the .app must ship it.
RESOURCE_BUNDLE := $(APP_NAME)_$(SRC_DIR).bundle
# The release artifacts land here: the disk images and the checksum file next to them.
RELEASE_DIR := release
CHECKSUMS := $(RELEASE_DIR)/checksums.txt

# The version comes from the command line: `make release VERSION=1.2.3`.
# It never comes from a file in the repository.
VERSION ?=

# The disk image names carry the architecture. The tap matches each asset by name,
# so they never change.
DMG_ARM64 := $(APP_NAME)-$(VERSION)-arm64.dmg
DMG_X86_64 := $(APP_NAME)-$(VERSION)-x86_64.dmg

# The bundles `make verify` checks. Both by default; a missing one is skipped, so
# a single per-architecture build can be checked on its own.
BUNDLES ?= $(APP_BUNDLES)

# SwiftPM's build engine records the deployment target in LC_BUILD_VERSION's sdk
# field. macOS reads that field to decide whether an app gets the Liquid Glass
# design, so a plain `swift build` looks like a macOS 15 binary to AppKit even
# when the newest SDK is installed. Restate the real SDK version at link time.
# Keep the deployment target in sync with `platforms` in Package.swift and
# LSMinimumSystemVersion in Info.plist.
MACOS_DEPLOYMENT_TARGET := 15.0
MACOS_SDK_VERSION := $(shell xcrun --sdk macosx --show-sdk-version)
LINK_SDK_FLAGS := -Xlinker -platform_version -Xlinker macos \
	-Xlinker $(MACOS_DEPLOYMENT_TARGET) -Xlinker $(MACOS_SDK_VERSION)

# The build number is the version without its dots and letters: 1.2.3 gives 123.
BUILD_NUMBER := $(shell printf '%s' '$(VERSION)' | tr -cd '0-9')

.PHONY: help build test verify run install app app-arm app-intel app-bundle-debug \
	run-bundle-debug dmg dmg-arm dmg-intel release-artifacts release-notes release \
	clean _require_version

.DEFAULT_GOAL := help

## help — list every target

help:
	@printf '%s\n' \
		'SwiftDefaults — build targets.' \
		'' \
		'  help                 List every target (default).' \
		'  build                Build the SwiftPM package.' \
		'  test                 Run the changelog check and the SwiftPM test suite.' \
		'  verify               Check each built bundle, its registry and its signature.' \
		'  run                  Install the bundle for this Mac into ~/Applications and launch it.' \
		'  install              Copy the bundle for this Mac into ~/Applications.' \
		'  app                  Build both shipping bundles and sign them ad-hoc.' \
		'  app-arm              Build the Apple silicon bundle into SwiftDefaults-arm64.app.' \
		'  app-intel            Build the Intel bundle into SwiftDefaults-x86_64.app.' \
		'  app-bundle-debug     Build the debug bundle into SwiftDefaults-Debug.app.' \
		'  run-bundle-debug     Build the debug bundle and open it.' \
		'  dmg                  Build both disk images into release/.' \
		'  dmg-arm              Build release/SwiftDefaults-<version>-arm64.dmg.' \
		'  dmg-intel            Build release/SwiftDefaults-<version>-x86_64.dmg.' \
		'  release-artifacts    Build both disk images and checksums.txt, then verify them.' \
		'  release-notes VERSION=x.y.z  Print the changelog section of a version.' \
		'  release VERSION=x.y.z  Bump the changelog, test, build, verify, commit and tag.' \
		'  clean                Remove the build output.' \
		'' \
		'Notes' \
		'  The app bundle is assembled by hand from the SwiftPM build. `swift build` alone' \
		'  gives a bare executable without the resources the app needs.' \
		'  The release ships one disk image per architecture, SwiftDefaults-<version>-arm64.dmg' \
		'  for Apple silicon and SwiftDefaults-<version>-x86_64.dmg for Intel. The tap matches' \
		'  each asset by name, so the names never change.' \
		'  The tweak registry ships in Contents/Resources, where the app reads it. The bundle' \
		'  holds nothing in the app root, because codesign seals only what lives in Contents/.' \
		'  CHANGELOG.md follows the shared shape and `make test` checks it.' \
		'  Signing stays ad-hoc: codesign --force --sign - --options runtime. There is no' \
		'  Developer ID identity and no notarization.' \
		'  `make release VERSION=1.2.3` moves [Unreleased] to the version, runs the tests,' \
		'  builds and verifies the artifacts, commits the bump and creates the tag v1.2.3.' \
		'  It prints the push commands and never pushes by itself.'

## build — build the package

build:
	swift build $(LINK_SDK_FLAGS)

## test — run the test suite

test:
	./scripts/changelog.sh check
	swift test $(LINK_SDK_FLAGS)

## verify — check the built bundles

verify:
	@found=0; \
	for bundle in $(BUNDLES); do \
		test -d "$$bundle" || continue; \
		found=1; \
		case "$$bundle" in \
			*arm64*) expected=arm64 ;; \
			*x86_64*) expected=x86_64 ;; \
			*) echo "error: $$bundle names no architecture; expected -arm64 or -x86_64."; exit 1 ;; \
		esac; \
		registry="$$bundle/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Resources/tweaks.json"; \
		test -f "$$registry" || { \
			echo "error: $$registry is missing; the app cannot load its registry."; \
			exit 1; \
		}; \
		test ! -e "$$bundle/$(RESOURCE_BUNDLE)" || { \
			echo "error: $$bundle/$(RESOURCE_BUNDLE) is in the app root; codesign will refuse it."; \
			exit 1; \
		}; \
		test -f "$$bundle/Contents/Resources/AppIcon.icns" || { \
			echo "error: $$bundle ships no AppIcon.icns."; \
			exit 1; \
		}; \
		count="$$(jq length "$$registry")"; \
		source_count="$$(jq length "$(SRC_DIR)/Resources/tweaks.json")"; \
		echo "$$bundle registry: $$count entries (source: $$source_count)"; \
		test "$$count" = "$$source_count" || { \
			echo "error: the registry in $$bundle holds $$count entries, the source holds $$source_count."; \
			exit 1; \
		}; \
		jq -e 'length >= 1 and all(.[]; .id and .category and .title and .description and .domain and .key and .type and (.onValue != null) and (.offValue != null))' "$$registry" >/dev/null || { \
			echo "error: the registry in $$bundle has an entry without a required field."; \
			exit 1; \
		}; \
		binary="$$bundle/Contents/MacOS/$(APP_NAME)"; \
		archs="$$(lipo -archs "$$binary")"; \
		echo "$$bundle architectures: $$archs (expected $$expected)"; \
		test "$$archs" = "$$expected" || { \
			echo "error: $$bundle is $$archs, but $$expected was expected."; \
			exit 1; \
		}; \
		if [ -n "$(strip $(VERSION))" ]; then \
			version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$$bundle/Contents/Info.plist")"; \
			echo "$$bundle version: $$version (expected $(VERSION))"; \
			test "$$version" = "$(VERSION)" || { \
				echo "error: $$bundle reports $$version, but $(VERSION) was expected."; \
				exit 1; \
			}; \
		else \
			echo "$$bundle version: $$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$$bundle/Contents/Info.plist") (no VERSION given)"; \
		fi; \
		codesign --verify --deep --strict "$$bundle" || exit 1; \
		echo "Verified $$bundle."; \
	done; \
	test "$$found" = 1 || { \
		echo "error: no app bundle found: $(BUNDLES). Run make app first."; \
		exit 1; \
	}

## run — install the bundle for this Mac and launch it

run: install
	open "$(INSTALL_APP)"

## install — copy the bundle for this Mac into ~/Applications

install: app
	@case "$$(uname -m)" in \
		arm64) bundle="$(APP_BUNDLE_ARM64)" ;; \
		x86_64) bundle="$(APP_BUNDLE_X86_64)" ;; \
		*) echo "error: uname -m printed $$(uname -m); expected arm64 or x86_64."; exit 1 ;; \
	esac; \
	mkdir -p "$(INSTALL_DIR)"; \
	rm -rf "$(INSTALL_APP)"; \
	cp -R "$$bundle" "$(INSTALL_APP)"; \
	echo "Installed $$bundle as $(INSTALL_APP)"

## app — the bundles the product ships

app: app-arm app-intel

## app-arm — the Apple silicon bundle

app-arm:
	$(call build_bundle,-c release --arch arm64 --scratch-path $(SPM_ARM_DIR),$(APP_BUNDLE_ARM64))

## app-intel — the Intel bundle

app-intel:
	$(call build_bundle,-c release --arch x86_64 --scratch-path $(SPM_INTEL_DIR),$(APP_BUNDLE_X86_64))

## app-bundle-debug — the bundle for development

app-bundle-debug:
	swift build $(LINK_SDK_FLAGS)
	$(call assemble_bundle,,$(APP_BUNDLE_DEBUG))
	@echo "Built $(APP_BUNDLE_DEBUG)"

## run-bundle-debug — build the debug bundle and open it

run-bundle-debug: app-bundle-debug
	open "$(APP_BUNDLE_DEBUG)"

## dmg — the disk images the tap installs

dmg: dmg-arm dmg-intel

## dmg-arm — the Apple silicon disk image

dmg-arm: _require_version app-arm
	$(call build_dmg,arm64,$(APP_BUNDLE_ARM64),$(DMG_ARM64))

## dmg-intel — the Intel disk image

dmg-intel: _require_version app-intel
	$(call build_dmg,x86_64,$(APP_BUNDLE_X86_64),$(DMG_X86_64))

## release-artifacts — the disk images and the checksum file the tap expects

release-artifacts: dmg
	@cd "$(RELEASE_DIR)" && shasum -a 256 "$(DMG_ARM64)" "$(DMG_X86_64)" > "$(notdir $(CHECKSUMS))"
	@cd "$(RELEASE_DIR)" && shasum -a 256 -c "$(notdir $(CHECKSUMS))"
	@echo "$(CHECKSUMS):"
	@cat "$(CHECKSUMS)"

## release-notes — print the changelog section of a version

release-notes:
	@if [ -z "$(strip $(VERSION))" ]; then \
		echo "error: make release-notes needs a version, for example: make release-notes VERSION=1.2.3"; \
		exit 1; \
	fi
	@./scripts/changelog.sh notes "$(VERSION)"

## release — bump, test, build, verify, commit and tag, without pushing

release: _require_version
	@APP_NAME="$(APP_NAME)" ./scripts/release.sh "$(VERSION)"

## clean — remove everything the build produces

clean:
	rm -rf "$(SPM_DIR)" "$(APP_BUNDLE_ARM64)" "$(APP_BUNDLE_X86_64)" "$(APP_BUNDLE_DEBUG)" "$(RELEASE_DIR)"
	@echo "Removed $(SPM_DIR)/, both app bundles, $(APP_BUNDLE_DEBUG)/ and $(RELEASE_DIR)/."

# The name of a release artifact carries the version, so the version must be there.
_require_version:
	@if [ -z "$(strip $(VERSION))" ]; then \
		echo "error: $(MAKECMDGOALS) needs a version, for example: make $(MAKECMDGOALS) VERSION=1.2.3"; \
		exit 1; \
	fi

# $(1) the swift build flags that pick the architecture and its scratch directory,
# $(2) the path of the bundle. The binary comes from the bin path of the same build,
# so the executable always matches the architecture that was just built.
define assemble_bundle
	@bin="$$(swift build $(1) --show-bin-path)/$(APP_NAME)"; \
	rm -rf "$(2)"; \
	mkdir -p "$(2)/Contents/MacOS" "$(2)/Contents/Resources"; \
	cp "$$bin" "$(2)/Contents/MacOS/$(APP_NAME)"; \
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
		-e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.wigglysheets.$(APP_NAME)/g' \
		-e 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' \
		"$(SRC_DIR)/Info.plist" > "$(2)/Contents/Info.plist"; \
	mkdir -p "$(2)/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Resources"; \
	cp "$(SRC_DIR)/Resources/tweaks.json" "$(2)/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Resources/tweaks.json"; \
	cp "$(ICON)" "$(2)/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Resources/AppIcon.icns"; \
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict>' \
		'<key>CFBundleIdentifier</key><string>com.wigglysheets.$(APP_NAME).resources</string>' \
		'<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>' \
		'<key>CFBundleName</key><string>$(RESOURCE_BUNDLE)</string>' \
		'<key>CFBundlePackageType</key><string>BNDL</string>' \
		'</dict></plist>' > "$(2)/Contents/Resources/$(RESOURCE_BUNDLE)/Contents/Info.plist"; \
	cp "$(ICON)" "$(2)/Contents/Resources/"; \
	if [ -f "$(ENTITLEMENTS)" ]; then cp "$(ENTITLEMENTS)" "$(2)/Contents/Resources/"; fi
endef

# $(1) the swift build flags that pick the architecture and its scratch directory,
# $(2) the path of the bundle. Stamps the version when one is given and signs ad-hoc.
define build_bundle
	swift build $(1) $(LINK_SDK_FLAGS)
	$(call assemble_bundle,$(1),$(2))
	@if [ -n "$(strip $(VERSION))" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(2)/Contents/Info.plist"; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(2)/Contents/Info.plist"; \
	fi
	codesign --force --sign - --options runtime "$(2)"
	codesign --verify --deep --strict "$(2)"
	@echo "Built and signed $(2)"
endef

# $(1) the architecture, $(2) the path of the bundle, $(3) the disk image name.
define build_dmg
	@stage="$(SPM_DIR)/dmg-stage-$(1)"; \
	rm -rf "$$stage"; \
	mkdir -p "$$stage" "$(RELEASE_DIR)"; \
	ditto "$(2)" "$$stage/$(APP_NAME).app"; \
	ln -s /Applications "$$stage/Applications"; \
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$$stage" -ov -format UDZO "$(RELEASE_DIR)/$(3)"; \
	rm -rf "$$stage"; \
	echo "Built $(RELEASE_DIR)/$(3)"
endef
