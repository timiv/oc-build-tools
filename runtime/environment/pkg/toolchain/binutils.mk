# =============================================================================
# binutils (native ARM) — cross-compiled to run on the ARM target
# =============================================================================
BINUTILS_URL       := https://ftp.gnu.org/gnu/binutils/binutils-$(BINUTILS_VERSION).tar.bz2
BINUTILS_SRC       := $(SRC_DIR)/binutils-$(BINUTILS_VERSION)
BINUTILS_BUILD_DIR := $(BUILD_DIR)/binutils-native

$(eval $(call user-target,binutils-native,\
	Cross-compile binutils $(BINUTILS_VERSION) to run on ARM target))

$(eval $(call download-rule,binutils,binutils-$(BINUTILS_VERSION).tar.bz2,$(BINUTILS_URL),$(BINUTILS_SRC)))

$(STAMP)/binutils-native: $(STAMP)/check-toolchain $(STAMP)/dl-binutils | $(CROSS_CC)
	@echo "==> Cross-compiling binutils $(BINUTILS_VERSION) for ARM target..."
	@mkdir -p $(BINUTILS_BUILD_DIR) $(STAMP)
	cd $(BINUTILS_BUILD_DIR) && \
		CC="$(CROSS_CC)" \
		CFLAGS="$(CROSS_CFLAGS)" \
		LDFLAGS="$(CROSS_LDFLAGS)" \
		$(BINUTILS_SRC)/configure \
			--host=$(CROSS_HOST) \
			--target=$(CROSS_HOST) \
			--build=$(BUILD_TRIPLET) \
			--prefix=/opt/open-centauri \
			--disable-nls \
			--disable-werror \
			--with-sysroot=/
	$(MAKE) -C $(BINUTILS_BUILD_DIR) -j$(JOBS)
	$(MAKE) -C $(BINUTILS_BUILD_DIR) install DESTDIR=$(NATIVE_GCC_PREFIX)
	@file=$(NATIVE_GCC_PREFIX)/opt/open-centauri/bin/ld && \
		file $$file | grep -q "ARM" || { echo "ERROR: binutils not ARM!"; exit 1; }
	@echo "==> binutils: ARM native build confirmed"
	@touch $@
