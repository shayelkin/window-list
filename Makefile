.PHONY: debug test release test-skip-liveax clean

XCODEPROJ := WindowList.xcodeproj/project.pbxproj
PRODUCTS := .build/xcode/Build/Products
DEBUG_BIN := $(PRODUCTS)/Debug/WindowList.app/Contents/MacOS/WindowList
RELEASE_BIN := $(PRODUCTS)/Release/WindowList.app/Contents/MacOS/WindowList
APP_BUNDLE := bin/WindowList.app
XCODEBUILD = xcodebuild -project WindowList.xcodeproj -scheme WindowList -destination 'platform=macOS' -derivedDataPath .build/xcode

PACKAGE_INPUTS := Package.swift Package.resolved $(shell find Sources -type f)
APP_INPUTS := project.yml $(PACKAGE_INPUTS) $(shell find App -type f)

debug: $(DEBUG_BIN)

release: $(APP_BUNDLE)

test:
	swift test

test-skip-liveax:
	swift test --skip LiveAXTests

clean:
	rm -rf .build bin/* WindowList.xcodeproj

$(XCODEPROJ): project.yml $(shell find App -type d)
	xcodegen generate

$(DEBUG_BIN): $(APP_INPUTS) | $(XCODEPROJ)
	$(XCODEBUILD) -configuration Debug build

$(RELEASE_BIN): $(APP_INPUTS) $(XCODEPROJ)
	$(XCODEBUILD) -configuration Release build

$(APP_BUNDLE): $(RELEASE_BIN)
	mkdir bin | true
	cp -R $(PRODUCTS)/Release/WindowList.app $(APP_BUNDLE)
