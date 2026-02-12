# =============================================================================
# pkg-macros.mk — Shared macros for the per-package build system
#
# Provides:
#   download-rule       — download + extract a source tarball
#   autotools-package   — standard configure/make/install for cross-compiled libs
#   check-toolchain     — sanity-check the vendor sysroot + cross-gcc
#   CROSS_TOOLCHAIN / CROSS_ENV / CROSS_ENV_FULL — environment snippets
#   REQ_STRIP / CROSSENV_ACTIVATE — pip helpers
# =============================================================================

# -- Helpers ------------------------------------------------------------------
HASH := \#
REQ_STRIP = sed -e 's/[[:space:]]*$(HASH).*$$//' -e '/^[[:space:]]*$$/d'
CROSSENV_ACTIVATE := . $(CROSSENV_DIR)/bin/activate &&

# -- Package registration -----------------------------------------------------
ALL_DOWNLOADS :=
ALL_TARGETS :=

# User-facing target definition: combines .PHONY, stamp dependency, and help registration
# Usage: $(eval $(call user-target,target-name,Description text,stamp-name))
#   stamp-name defaults to target-name if omitted
define user-target
.PHONY: $(strip $(1))
$(strip $(1)): $$(STAMP)/$(strip $(or $(3),$(1)))
ALL_TARGETS += $(strip $(1))
HELP_$(strip $(1)) := $(strip $(2))
endef

# -- Common cross-compilation environment ------------------------------------
define CROSS_TOOLCHAIN
CC="$(CROSS_CC)" CXX="$(CROSS_CXX)" AR="$(CROSS_AR)" RANLIB="$(CROSS_RANLIB)"
endef

define CROSS_ENV
$(CROSS_TOOLCHAIN) \
CFLAGS="$(CROSS_CFLAGS)" CXXFLAGS="$(CROSS_CXXFLAGS)" LDFLAGS="$(CROSS_LDFLAGS)"
endef

define CROSS_ENV_FULL
$(CROSS_TOOLCHAIN) \
CFLAGS="$(CROSS_CFLAGS) -I$(TARGET_PREFIX)/include -I$(VENDOR_SYSROOT)/include" \
CXXFLAGS="$(CROSS_CXXFLAGS) -I$(TARGET_PREFIX)/include -I$(VENDOR_SYSROOT)/include" \
CPPFLAGS="-I$(TARGET_PREFIX)/include -I$(VENDOR_SYSROOT)/include -I$(TARGET_PREFIX)/include/python$(PYTHON_MM)" \
LDFLAGS="$(CROSS_LDFLAGS) -L$(TARGET_PREFIX)/lib" \
PKG_CONFIG_LIBDIR="$(TARGET_PREFIX)/lib/pkgconfig:$(VENDOR_SYSROOT)/lib/pkgconfig" \
PKG_CONFIG_PATH="" \
PKG_CONFIG_SYSROOT_DIR="$(VENDOR_SYSROOT)"
endef

# =============================================================================
# download-rule macro
#   $(1) = stamp name        (e.g. zlib)
#   $(2) = tarball filename  (e.g. zlib-1.3.1.tar.gz)
#   $(3) = download URL
#   $(4) = expected source directory after extraction
#
# Automatically registers the download stamp in ALL_DOWNLOADS variable.
# =============================================================================
define download-rule
ALL_DOWNLOADS += $$(STAMP)/dl-$(1)
$$(STAMP)/dl-$(1):
	@echo "==> Downloading $(2)..."
	@mkdir -p $$(DL_DIR) $$(SRC_DIR) $$(STAMP)
	$$(CURL) -L --fail --retry 3 -o $$(DL_DIR)/$(2) $(3)
	@rm -rf $(4)
	$$(TAR) xf $$(DL_DIR)/$(2) -C $$(SRC_DIR)
	@touch $$@
endef

# =============================================================================
# autotools-package macro — standard configure/make/make-install
#   $(1) = UPPER-CASE variable prefix  (e.g. ZLIB)
#   $(2) = lower-case stamp name       (e.g. zlib)
#
# The calling .mk file must set:
#   $(1)_VERSION        — package version (for log messages)
#   $(1)_SRC            — path to extracted source tree
#   $(1)_BUILD_DIR      — out-of-tree build directory
#   $(1)_CONFIGURE_ARGS — arguments to ./configure
#   $(1)_DEPENDS        — list of stamp-names this package depends on
# =============================================================================
define autotools-package
$$(STAMP)/$(2): $$(foreach d,$$($(1)_DEPENDS),$$(STAMP)/$$(d)) $$(STAMP)/dl-$(2) | $$(CROSS_CC)
	@echo "==> Cross-compiling $(2) $$($(1)_VERSION)..."
	@mkdir -p $$($(1)_BUILD_DIR)
	cd $$($(1)_BUILD_DIR) && \
		CC="$$(CROSS_CC)" CFLAGS="$$(CROSS_CFLAGS)" LDFLAGS="$$(CROSS_LDFLAGS)" \
		$$($(1)_SRC)/configure $$($(1)_CONFIGURE_ARGS)
	$$(MAKE) -C $$($(1)_BUILD_DIR) -j$$(JOBS)
	$$(MAKE) -C $$($(1)_BUILD_DIR) install
	@touch $$@
endef

# =============================================================================
# Toolchain sanity checks (cached per STAMP_KEY)
# =============================================================================
MESON_CROSS := $(BUILD_DIR)/meson-cross.ini

$(STAMP)/check-toolchain: $(STAMP)/cross-gcc $(STAMP)/vendor-toolchain
	@mkdir -p $(STAMP)
	@test -d "$(VENDOR_SYSROOT)" || { echo "ERROR: VENDOR_SYSROOT not found: $(VENDOR_SYSROOT)"; exit 1; }
	@test -d "$(VENDOR_GCC_RT)" || { echo "ERROR: VENDOR_GCC_RT not found: $(VENDOR_GCC_RT)"; exit 1; }
	@test -x "$(CROSS_GCC_PREFIX)/bin/arm-linux-gnueabihf-gcc" \
		|| { echo "ERROR: cross-gcc not built yet. Run 'make cross-gcc' first."; exit 1; }
	@touch $@

# =============================================================================
# Meson cross-file for numpy and other meson-based packages
# =============================================================================
$(MESON_CROSS): $(STAMP)/check-toolchain | $(BUILD_DIR)
	@echo "==> Generating meson cross-file..."
	@{ \
	echo "[host_machine]"; \
	echo "system     = 'linux'"; \
	echo "cpu_family = 'arm'"; \
	echo "cpu        = 'cortex-a7'"; \
	echo "endian     = 'little'"; \
	echo ""; \
	echo "[binaries]"; \
	echo "c       = '$(CROSS_CC)'"; \
	echo "cpp     = '$(CROSS_CXX)'"; \
	echo "ar      = '$(CROSS_AR)'"; \
	echo "strip   = '$(CROSS_STRIP)'"; \
	echo "pkgconfig = 'pkg-config'"; \
	echo "cython  = 'cython'"; \
	echo ""; \
	echo "[built-in options]"; \
	echo "c_args      = ['-O2', '-I$(TARGET_PREFIX)/include']"; \
	echo "c_link_args = ['-L$(VENDOR_SYSROOT)/lib', '-Wl,-rpath-link,$(VENDOR_SYSROOT)/lib', '-L$(TARGET_PREFIX)/lib', '-Wl,-rpath-link,$(TARGET_PREFIX)/lib']"; \
	echo "cpp_args    = ['-O2', '-I$(TARGET_PREFIX)/include']"; \
	echo "cpp_link_args = ['-L$(VENDOR_SYSROOT)/lib', '-Wl,-rpath-link,$(VENDOR_SYSROOT)/lib', '-L$(TARGET_PREFIX)/lib', '-Wl,-rpath-link,$(TARGET_PREFIX)/lib']"; \
	echo ""; \
	echo "[properties]"; \
	echo "longdouble_format = 'IEEE_DOUBLE_LE'"; \
	} > $@
