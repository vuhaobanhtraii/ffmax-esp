# Set target architectures
ARCHS = arm64

# Support both Rootless and Rootful packaging
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FreeFireMaxESP

FreeFireMaxESP_FILES = Tweak.xm
FreeFireMaxESP_CFLAGS = -fobjc-arc
FreeFireMaxESP_CCFLAGS = -std=c++17
FreeFireMaxESP_FRAMEWORKS = UIKit CoreGraphics

# Ignore warnings and deprecation errors during compilation
ADDITIONAL_CFLAGS = -Wno-error -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function

include $(THEOS_MAKE_PATH)/tweak.mk
