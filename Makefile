APP := SwiftDefaults
SRC_DIR := $(APP)
BUILD_DIR := .build/debug
APP_BUNDLE := $(APP).app
APP_BUNDLE_DEBUG := $(APP)-Debug.app
ICON := $(SRC_DIR)/Resources/AppIcon.icns
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

app-bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP) $(APP_BUNDLE)/Contents/MacOS/$(APP)
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP)/g' -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.wigglysheets.$(APP)/g' -e 's/$$(PRODUCT_NAME)/$(APP)/g' $(SRC_DIR)/Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	cp $(SRC_DIR)/Resources/tweaks.json $(APP_BUNDLE)/Contents/Resources/
	cp $(ICON) $(APP_BUNDLE)/Contents/Resources/

app-bundle-debug: build
	rm -rf $(APP_BUNDLE_DEBUG)
	mkdir -p $(APP_BUNDLE_DEBUG)/Contents/MacOS $(APP_BUNDLE_DEBUG)/Contents/Resources
	cp $(BUILD_DIR)/$(APP) $(APP_BUNDLE_DEBUG)/Contents/MacOS/$(APP)
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP)/g' -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.wigglysheets.$(APP)/g' -e 's/$$(PRODUCT_NAME)/$(APP)/g' $(SRC_DIR)/Info.plist > $(APP_BUNDLE_DEBUG)/Contents/Info.plist
	cp $(SRC_DIR)/Resources/tweaks.json $(APP_BUNDLE_DEBUG)/Contents/Resources/
	cp $(ICON) $(APP_BUNDLE_DEBUG)/Contents/Resources/

run-bundle-debug: app-bundle-debug
	open $(APP_BUNDLE_DEBUG)
