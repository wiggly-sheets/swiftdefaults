APP := SwiftDefaults
SRC_DIR := $(APP)
BUILD_DIR := .build/debug
APP_BUNDLE := $(APP).app

.PHONY: build run clean release app-bundle

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
	sed -e 's/$$(EXECUTABLE_NAME)/$(APP)/g' -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.example.$(APP)/g' -e 's/$$(PRODUCT_NAME)/$(APP)/g' $(SRC_DIR)/Info.plist > $(APP_BUNDLE)/Contents/Info.plist
	cp $(SRC_DIR)/Resources/tweaks.json $(APP_BUNDLE)/Contents/Resources/
