# Set target architectures: arm64 is standard for modern iOS devices
ARCHS = arm64
TARGET = iphoneos:clang:latest:14.0

# Support both Rootless and Rootful packaging
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FreeFireMaxESP

FreeFireMaxESP_FILES = Tweak.xm
FreeFireMaxESP_CFLAGS = -fobjc-arc -std=c++17
FreeFireMaxESP_FRAMEWORKS = UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
