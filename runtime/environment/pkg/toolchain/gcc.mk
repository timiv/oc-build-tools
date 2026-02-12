# =============================================================================
# GCC (native ARM) — cross-compiled to run on the ARM target
#
# Uses vendor GCC 6.4.1 as the cross-compiler because GCC 6.x source doesn't
# compile with modern host compilers (C++ strictness issues).
# =============================================================================
GCC_NATIVE_URL       := https://ftp.gnu.org/gnu/gcc/gcc-$(GCC_NATIVE_VERSION)/gcc-$(GCC_NATIVE_VERSION).tar.xz
GCC_NATIVE_SRC       := $(SRC_DIR)/gcc-$(GCC_NATIVE_VERSION)
GCC_NATIVE_BUILD_DIR := $(BUILD_DIR)/gcc-native

# Vendor cross-compiler (only used by this target)
VENDOR_CC      := $(VENDOR_SYSROOT)/bin/arm-openwrt-linux-gnueabi-gcc
VENDOR_CXX     := $(VENDOR_SYSROOT)/bin/arm-openwrt-linux-gnueabi-g++
VENDOR_AR      := $(VENDOR_SYSROOT)/bin/arm-openwrt-linux-gnueabi-ar
VENDOR_RANLIB  := $(VENDOR_SYSROOT)/bin/arm-openwrt-linux-gnueabi-ranlib

$(eval $(call user-target,gcc-native,\
	Cross-compile GCC $(GCC_NATIVE_VERSION) to run on ARM target))

$(eval $(call user-target,native-toolchain,\
	Build complete native ARM toolchain (binutils + gcc),\
	gcc-native))

$(eval $(call download-rule,gcc-native,gcc-$(GCC_NATIVE_VERSION).tar.xz,$(GCC_NATIVE_URL),$(GCC_NATIVE_SRC)))

$(STAMP)/gcc-native: $(STAMP)/binutils-native $(STAMP)/dl-gcc-native
	@echo "==> Downloading GCC $(GCC_NATIVE_VERSION) prerequisites (GMP, MPFR, MPC) if needed..."
	@test -d $(GCC_NATIVE_SRC)/gmp && test -d $(GCC_NATIVE_SRC)/mpfr && test -d $(GCC_NATIVE_SRC)/mpc \
		|| { cd $(GCC_NATIVE_SRC) && ./contrib/download_prerequisites; }
	@rm -rf $(GCC_NATIVE_SRC)/isl
	@echo "==> Cross-compiling gcc $(GCC_NATIVE_VERSION) for ARM target..."
	@echo "    (Using vendor GCC 6.4.1 as cross-compiler)"
	@echo "    (This will take 15-30 minutes...)"
	@rm -rf $(GCC_NATIVE_BUILD_DIR)
	@mkdir -p $(GCC_NATIVE_BUILD_DIR) $(STAMP)
	cd $(GCC_NATIVE_BUILD_DIR) && \
		export STAGING_DIR="$(VENDOR_SYSROOT)" && \
		CC_FOR_BUILD="/usr/bin/gcc -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion" \
		CXX_FOR_BUILD="/usr/bin/g++" \
		CFLAGS_FOR_BUILD="-O2" \
		CXXFLAGS_FOR_BUILD="-O2" \
		LDFLAGS_FOR_BUILD="" \
		AR_FOR_BUILD="ar" \
		CC="$(VENDOR_CC)" \
		CXX="$(VENDOR_CXX)" \
		AR="$(VENDOR_AR)" \
		RANLIB="$(VENDOR_RANLIB)" \
		CFLAGS="-O2" \
		CXXFLAGS="-O2 -fpermissive" \
		LDFLAGS="" \
		PATH="$(NATIVE_GCC_PREFIX)/opt/open-centauri/bin:$$PATH" \
		$(GCC_NATIVE_SRC)/configure \
			--host=$(CROSS_HOST) \
			--target=$(CROSS_HOST) \
			--build=$(BUILD_TRIPLET) \
			--prefix=/opt/open-centauri \
			--with-sysroot=/ \
			--enable-languages=c \
			--disable-multilib \
			--disable-libsanitizer \
			--disable-libquadmath \
			--disable-libgomp \
			--disable-libssp \
			--disable-nls \
			--disable-bootstrap \
			--disable-isl \
			--disable-werror \
			--with-arch=armv7-a \
			--with-fpu=vfpv4 \
			--with-float=hard \
			--with-stage1-ldflags='' \
			--with-boot-ldflags=''
	export STAGING_DIR="$(VENDOR_SYSROOT)" && \
		$(MAKE) -C $(GCC_NATIVE_BUILD_DIR) -j$(JOBS) all-gcc
	export STAGING_DIR="$(VENDOR_SYSROOT)" && \
		$(MAKE) -C $(GCC_NATIVE_BUILD_DIR) install-gcc DESTDIR=$(NATIVE_GCC_PREFIX)
	@file=$(NATIVE_GCC_PREFIX)/opt/open-centauri/bin/gcc && \
		file $$file | grep -q "ARM" || { echo "ERROR: gcc not ARM!"; exit 1; }
	@echo "==> gcc: ARM native build confirmed"
	@touch $@
