# =============================================================================
# zlib — compression library
# =============================================================================
ZLIB_VERSION       := $(ZLIB_VERSION)
ZLIB_URL           := https://zlib.net/zlib-$(ZLIB_VERSION).tar.gz
ZLIB_SRC           := $(SRC_DIR)/zlib-$(ZLIB_VERSION)
ZLIB_BUILD_DIR     := $(BUILD_DIR)/zlib
ZLIB_CONFIGURE_ARGS := --prefix=$(TARGET_PREFIX)
ZLIB_DEPENDS       := check-toolchain

$(eval $(call download-rule,zlib,zlib-$(ZLIB_VERSION).tar.gz,$(ZLIB_URL),$(ZLIB_SRC)))
$(eval $(call autotools-package,ZLIB,zlib))
