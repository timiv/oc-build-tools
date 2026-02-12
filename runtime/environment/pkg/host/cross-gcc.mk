# =============================================================================
# Cross-GCC 14 — built from source against vendor sysroot
#
# Runs on the build host (x86_64), produces ARM hard-float code.
# --with-sysroot ensures libgcc and libstdc++ are built against the
# vendor's glibc 2.23, so everything is runtime-compatible with the target.
# =============================================================================
GCC_CROSS_URL       := https://ftp.gnu.org/gnu/gcc/gcc-$(GCC_CROSS_VERSION)/gcc-$(GCC_CROSS_VERSION).tar.xz
GCC_CROSS_SRC       := $(SRC_DIR)/gcc-$(GCC_CROSS_VERSION)
GCC_CROSS_BUILD_DIR := $(BUILD_DIR)/gcc-cross

$(eval $(call user-target,cross-gcc,\
	Build GCC $(GCC_CROSS_VERSION) cross-compiler for ARM))

$(eval $(call download-rule,gcc-cross,gcc-$(GCC_CROSS_VERSION).tar.xz,$(GCC_CROSS_URL),$(GCC_CROSS_SRC)))

$(STAMP)/cross-gcc: $(STAMP)/dl-gcc-cross $(STAMP)/vendor-toolchain
	@echo "==> Downloading GCC $(GCC_CROSS_VERSION) prerequisites (GMP, MPFR, MPC)..."
	@test -d $(GCC_CROSS_SRC)/gmp && test -d $(GCC_CROSS_SRC)/mpfr && test -d $(GCC_CROSS_SRC)/mpc \
		|| { cd $(GCC_CROSS_SRC) && ./contrib/download_prerequisites; }
	@rm -rf $(GCC_CROSS_SRC)/isl
	@echo "==> Building cross-GCC $(GCC_CROSS_VERSION) (host=x86_64, target=arm-linux-gnueabihf)..."
	@echo "    (sysroot: $(VENDOR_SYSROOT))"
	@echo "    (This will take 15-30 minutes...)"
	@rm -rf $(GCC_CROSS_BUILD_DIR)
	@mkdir -p $(GCC_CROSS_BUILD_DIR) $(STAMP)
	cd $(GCC_CROSS_BUILD_DIR) && \
		$(GCC_CROSS_SRC)/configure \
			--target=arm-linux-gnueabihf \
			--build=$(BUILD_TRIPLET) \
			--host=$(BUILD_TRIPLET) \
			--prefix=$(CROSS_GCC_PREFIX) \
			--with-sysroot=$(VENDOR_SYSROOT) \
			--with-native-system-header-dir=/include \
			--enable-languages=c,c++ \
			--disable-multilib \
			--disable-libsanitizer \
			--disable-libquadmath \
			--disable-libgomp \
			--disable-nls \
			--disable-bootstrap \
			--disable-isl \
			--disable-werror \
			--with-arch=armv7-a \
			--with-fpu=vfpv4 \
			--with-float=hard
	$(MAKE) -C $(GCC_CROSS_BUILD_DIR) -j$(JOBS)
	$(MAKE) -C $(GCC_CROSS_BUILD_DIR) install
	@echo "==> Symlinking system ARM binutils into cross-gcc prefix..."
	@mkdir -p $(CROSS_GCC_PREFIX)/arm-linux-gnueabihf/bin
	@for tool in as ld ld.bfd nm objcopy objdump ranlib readelf strip ar; do \
		ln -sf /usr/bin/arm-linux-gnueabihf-$$tool \
			$(CROSS_GCC_PREFIX)/arm-linux-gnueabihf/bin/$$tool; \
	done
	@echo "==> cross-gcc $(GCC_CROSS_VERSION) installed to $(CROSS_GCC_PREFIX)"
	@touch $@

# -- Wrapper scripts (bake in sysroot, arch flags, runtime paths) -------------
$(CROSS_CC): $(STAMP)/cross-gcc | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	@{ \
	echo '#!/bin/sh'; \
	echo 'exec $(CROSS_GCC_PREFIX)/bin/arm-linux-gnueabihf-gcc \'; \
	echo '    --sysroot=$(VENDOR_SYSROOT) \'; \
	echo '    -B$(CROSS_GCC_RT) \'; \
	echo '    -B$(VENDOR_SYSROOT)/lib/ \'; \
	echo '    $(ARCH_FLAGS) \'; \
	echo '    "$$@"'; \
	} > $@
	@chmod +x $@

$(CROSS_CXX): $(STAMP)/cross-gcc | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	@{ \
	echo '#!/bin/sh'; \
	echo 'exec $(CROSS_GCC_PREFIX)/bin/arm-linux-gnueabihf-g++ \'; \
	echo '    --sysroot=$(VENDOR_SYSROOT) \'; \
	echo '    -B$(CROSS_GCC_RT) \'; \
	echo '    -B$(VENDOR_SYSROOT)/lib/ \'; \
	echo '    $(ARCH_FLAGS) \'; \
	echo '    "$$@"'; \
	} > $@
	@chmod +x $@
