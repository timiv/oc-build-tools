# =============================================================================
# libffi — foreign function interface library
# =============================================================================
LIBFFI_VERSION       := $(LIBFFI_VERSION)
LIBFFI_URL           := https://github.com/libffi/libffi/releases/download/v$(LIBFFI_VERSION)/libffi-$(LIBFFI_VERSION).tar.gz
LIBFFI_SRC           := $(SRC_DIR)/libffi-$(LIBFFI_VERSION)
LIBFFI_BUILD_DIR     := $(BUILD_DIR)/libffi
LIBFFI_CONFIGURE_ARGS := \
	--host=$(CROSS_HOST) \
	--prefix=$(TARGET_PREFIX) \
	--disable-static --enable-shared
LIBFFI_DEPENDS       := check-toolchain

$(eval $(call download-rule,libffi,libffi-$(LIBFFI_VERSION).tar.gz,$(LIBFFI_URL),$(LIBFFI_SRC)))
$(eval $(call autotools-package,LIBFFI,libffi))
