# 充电上限后台服务：以 root 常驻，到上限停充、掉到恢复线再充（见 main.m）
include $(THEOS)/makefiles/common.mk

TOOL_NAME = xrhead
xrhead_FILES = main.m
xrhead_CFLAGS = -fobjc-arc
xrhead_LIBRARIES = sqlite3   # 只读系统电池记录（耗电排行）
ifneq ($(FINALPACKAGE),1)
xrhead_CFLAGS += -DXRH_DEBUG=1
endif
xrhead_CODESIGN_FLAGS = -Sentitlements.plist
xrhead_INSTALL_PATH = /usr/libexec/xrhea

include $(THEOS_MAKE_PATH)/tool.mk
