include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = xrheaPrefs
# XRBattery 和插件共用同一份读数代码
xrheaPrefs_FILES = $(wildcard *.m) ../Shared/XRBattery.m ../Shared/XRHEvents.m
xrheaPrefs_FRAMEWORKS = UIKit
xrheaPrefs_PRIVATE_FRAMEWORKS = Preferences
xrheaPrefs_INSTALL_PATH = /Library/PreferenceBundles
xrheaPrefs_CFLAGS = -fobjc-arc -I../Shared

include $(THEOS_MAKE_PATH)/bundle.mk
