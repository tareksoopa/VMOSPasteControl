# Build on macOS with Xcode Command Line Tools installed.
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CLANG := $(shell xcrun -f clang)
TARGET := arm64-apple-ios16.0

all: VMOSPasteControl.dylib

VMOSPasteControl.dylib: VMOSPasteControl.m
	$(CLANG) -target $(TARGET) -isysroot $(SDK) -fobjc-arc -dynamiclib \
		-framework UIKit -framework Foundation \
		-install_name @rpath/VMOSPasteControl.dylib \
		-o $@ $<
	codesign -s - $@

clean:
	rm -f VMOSPasteControl.dylib
