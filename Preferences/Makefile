# Match the root target explicitly: aggregate sub-makes do not inherit
# ordinary Makefile variables from the parent make unless exported.
ARCHS = arm64
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LumenBoardPrefs
LumenBoardPrefs_FILES = LBRootListController.m LBTendiesValidator.m ../Shared/LBPaths.m
LumenBoardPrefs_INSTALL_PATH = /Library/PreferenceBundles
LumenBoardPrefs_FRAMEWORKS = UIKit PhotosUI Photos UniformTypeIdentifiers
LumenBoardPrefs_PRIVATE_FRAMEWORKS = Preferences
LumenBoardPrefs_CFLAGS = -fobjc-arc -Wall -Wextra
LumenBoardPrefs_LIBRARIES = z
LumenBoardPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
