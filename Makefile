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

app-bundle: release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(RELEASE_DIR)/$(APP) $(APP_BUNDLE)/Contents/MacOS/$(APP)
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP)/g' -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.wigglysheets.$(APP)/g' -e 's/$$(PRODUCT_NAME)/$(APP)/g' $(SRC_DIR)/Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	cp -R $(RELEASE_DIR)/$(RESOURCE_BUNDLE) $(APP_BUNDLE)/Contents/Resources/
	cp $(ICON) $(APP_BUNDLE)/Contents/Resources/
	if [ -f $(ENTITLEMENTS) ]; then cp $(ENTITLEMENTS) $(APP_BUNDLE)/Contents/Resources/; fi

app-bundle-debug: build
	rm -rf $(APP_BUNDLE_DEBUG)
	mkdir -p $(APP_BUNDLE_DEBUG)/Contents/MacOS $(APP_BUNDLE_DEBUG)/Contents/Resources
	cp $(BUILD_DIR)/$(APP) $(APP_BUNDLE_DEBUG)/Contents/MacOS/$(APP)
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP)/g' -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.wigglysheets.$(APP)/g' -e 's/$$(PRODUCT_NAME)/$(APP)/g' $(SRC_DIR)/Info.plist > $(APP_BUNDLE_DEBUG)/Contents/Info.plist
	cp -R $(BUILD_DIR)/$(RESOURCE_BUNDLE) $(APP_BUNDLE_DEBUG)/Contents/Resources/
	cp $(ICON) $(APP_BUNDLE_DEBUG)/Contents/Resources/
	if [ -f $(ENTITLEMENTS) ]; then cp $(ENTITLEMENTS) $(APP_BUNDLE_DEBUG)/Contents/Resources/; fi

run-bundle-debug: app-bundle-debug
	open $(APP_BUNDLE_DEBUG)
