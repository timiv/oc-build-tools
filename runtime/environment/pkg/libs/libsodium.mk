# =============================================================================
# libsodium — runtime dependency of libnacl / moonraker
# =============================================================================
LIBSODIUM_URL            := https://github.com/jedisct1/libsodium/releases/download/$(LIBSODIUM_VERSION)-RELEASE/libsodium-$(LIBSODIUM_VERSION).tar.gz
LIBSODIUM_SRC            := $(SRC_DIR)/libsodium-$(LIBSODIUM_VERSION)
LIBSODIUM_BUILD_DIR      := $(BUILD_DIR)/libsodium
LIBSODIUM_CONFIGURE_ARGS := \
	--host=$(CROSS_HOST) \
	--prefix=$(TARGET_PREFIX) \
	--disable-static --enable-shared
LIBSODIUM_DEPENDS        := check-toolchain

.PHONY: libsodium
libsodium: $(STAMP)/libsodium

$(eval $(call download-rule,libsodium,libsodium-$(LIBSODIUM_VERSION).tar.gz,$(LIBSODIUM_URL),$(LIBSODIUM_SRC)))
$(eval $(call autotools-package,LIBSODIUM,libsodium))
