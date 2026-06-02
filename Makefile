export THEOS ?= /home/nocone/theos
export THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SendMyBattery
SendMyBattery_FILES = Sources/Tweak.xm
SendMyBattery_CFLAGS = -fobjc-arc
SendMyBattery_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
