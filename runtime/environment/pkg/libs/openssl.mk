# =============================================================================
# OpenSSL — provides _ssl, _hashlib modules for Python
# Uses its own ./Configure script (not autotools), so a custom recipe is used.
# =============================================================================
OPENSSL_URL       := https://github.com/openssl/openssl/releases/download/openssl-$(OPENSSL_VERSION)/openssl-$(OPENSSL_VERSION).tar.gz
OPENSSL_SRC       := $(SRC_DIR)/openssl-$(OPENSSL_VERSION)
OPENSSL_BUILD_DIR := $(BUILD_DIR)/openssl

.PHONY: openssl
openssl: $(STAMP)/openssl

$(eval $(call download-rule,openssl,openssl-$(OPENSSL_VERSION).tar.gz,$(OPENSSL_URL),$(OPENSSL_SRC)))

$(STAMP)/openssl: $(STAMP)/check-toolchain $(STAMP)/dl-openssl | $(CROSS_CC)
	@echo "==> Cross-compiling OpenSSL $(OPENSSL_VERSION)..."
	@rm -rf $(OPENSSL_BUILD_DIR)
	@cp -a $(OPENSSL_SRC) $(OPENSSL_BUILD_DIR)
	cd $(OPENSSL_BUILD_DIR) && \
		CC="$(CROSS_CC)" AR="$(CROSS_AR)" RANLIB="$(CROSS_RANLIB)" \
		./Configure linux-armv4 \
			--prefix=$(TARGET_PREFIX) \
			--openssldir=$(TARGET_PREFIX)/ssl \
			--libdir=lib \
			shared no-tests no-async \
			-Wl,-rpath-link,$(VENDOR_SYSROOT)/lib
	$(MAKE) -C $(OPENSSL_BUILD_DIR) -j$(JOBS)
	$(MAKE) -C $(OPENSSL_BUILD_DIR) install_sw
	@touch $@
