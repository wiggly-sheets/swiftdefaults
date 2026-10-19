APP := SwiftDefaults
SRC_DIR := $(APP)
BUILD_DIR := .build/debug
RELEASE_DIR := .build/release
APP_BUNDLE := $(APP).app
APP_BUNDLE_DEBUG := $(APP)-Debug.app
ICON := $(SRC_DIR)/Resources/AppIcon.icns
ENTITLEMENTS := $(SRC_DIR)/$(APP).entitlements
# SwiftPM generates this; Bundle.module fatalErrors without it, so the .app must ship it.
RESOURCE_BUNDLE := $(APP)_$(SRC_DIR).bundle
# Bundle.module looks for the resource bundle in the app root (SwiftPM 6.0-6.3) or in
# Contents/Resources (6.4+), and SwiftPM's own bundle layout differs between toolchains
# (flat on 6.2, Contents/Resources on 6.4). Build the classic macOS layout by hand and ship
# it in both places, so the app finds the registry on every toolchain.
RES_BUNDLE_CONTENTS = mkdir -p $(RES_BUNDLE_DIR)/Contents/Resources && \
cp $(SRC_DIR)/Resources/tweaks.json $(RES_BUNDLE_DIR)/Contents/Resources/tweaks.json && \
cp $(ICON) $(RES_BUNDLE_DIR)/Contents/Resources/AppIcon.icns && \
printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
'<plist version="1.0"><dict>' \
'<key>CFBundleIdentifier</key><string>com.wigglysheets.$(APP).resources</string>' \
'<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>' \
'<key>CFBundleName</key><string>$(APP)_$(SRC_DIR)</string>' \
'<key>CFBundlePackageType</key><string>BNDL</string>' \
'</dict></plist>' > $(RES_BUNDLE_DIR)/Contents/Info.plist && \
cp -R $(RES_BUNDLE_DIR) $(RES_BUNDLE_ROOT)/
# Regenerate icon: rsvg-convert -w 1024 -h 1024 Assets/icon-concept.svg -o /tmp/icon1024.png, then sips sizes into AppIcon.iconset, then iconutil -c icns

.PHONY: build run clean release app-bundle app-bundle-debug run-bundle-debug

build:
	swift build

run:
	swift run

clean:
	swift package clean

release:
	swift build -c release

app-bundle: RES_BUNDLE_DIR = $(APP_BUNDLE)/Contents/Resources/$(RESOURCE_BUNDLE)
app-bundle: RES_BUNDLE_ROOT = $(APP_BUNDLE)
app-bundle-debug: RES_BUNDLE_DIR = $(APP_BUNDLE_DEBUG)/Contents/Resources/$(RESOURCE_BUNDLE)
app-bundle-debug: RES_BUNDLE_ROOT = $(APP_BUNDLE_DEBUG)

app-bundle: release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(RELEASE_DIR)/$(APP) $(APP_BUNDLE)/Contents/MacOS/$(APP)
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP)/g' -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.wigglysheets.$(APP)/g' -e 's/$$(PRODUCT_NAME)/$(APP)/g' $(SRC_DIR)/Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	$(RES_BUNDLE_CONTENTS)
	cp $(ICON) $(APP_BUNDLE)/Contents/Resources/
	if [ -f $(ENTITLEMENTS) ]; then cp $(ENTITLEMENTS) $(APP_BUNDLE)/Contents/Resources/; fi

app-bundle-debug: build
	rm -rf $(APP_BUNDLE_DEBUG)
	mkdir -p $(APP_BUNDLE_DEBUG)/Contents/MacOS $(APP_BUNDLE_DEBUG)/Contents/Resources
	cp $(BUILD_DIR)/$(APP) $(APP_BUNDLE_DEBUG)/Contents/MacOS/$(APP)
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP)/g' -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.wigglysheets.$(APP)/g' -e 's/$$(PRODUCT_NAME)/$(APP)/g' $(SRC_DIR)/Info.plist > $(APP_BUNDLE_DEBUG)/Contents/Info.plist
	$(RES_BUNDLE_CONTENTS)
	cp $(ICON) $(APP_BUNDLE_DEBUG)/Contents/Resources/
	if [ -f $(ENTITLEMENTS) ]; then cp $(ENTITLEMENTS) $(APP_BUNDLE_DEBUG)/Contents/Resources/; fi

run-bundle-debug: app-bundle-debug
	open $(APP_BUNDLE_DEBUG)
