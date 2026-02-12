# =============================================================================
# Moonraker pip packages — cross-compiled via crossenv
# =============================================================================
$(eval $(call user-target,packages-moonraker,\
	Cross-compile Moonraker pip packages (Pillow etc)))

# Split requirements: Pillow needs special build flags
REQS_MOONRAKER_BASE   := $(BUILD_DIR)/requirements-moonraker-base.txt
REQS_MOONRAKER_PILLOW := $(BUILD_DIR)/requirements-moonraker-pillow.txt

$(REQS_MOONRAKER_BASE): $(REQS_MOONRAKER) | $(BUILD_DIR)
	@echo "==> Generating $(notdir $@)..."
	@$(REQ_STRIP) $< | grep -ivE '^[[:space:]]*pillow([^[:alnum:]_.-]|$$)' > $@

$(REQS_MOONRAKER_PILLOW): $(REQS_MOONRAKER) | $(BUILD_DIR)
	@echo "==> Generating $(notdir $@)..."
	@$(REQ_STRIP) $< | grep -iE '^[[:space:]]*pillow([^[:alnum:]_.-]|$$)' > $@

# Pillow 12+ uses --config-settings instead of DISABLE_* env vars.
# platform-guessing=disable prevents host /usr/include from leaking into
# the ARM cross-build.  The remaining flags disable optional image codecs
# whose libraries are not available in the vendor sysroot.
PILLOW_CONFIG_SETTINGS := \
	--config-settings=platform-guessing=disable \
	--config-settings=jpeg=disable \
	--config-settings=tiff=disable \
	--config-settings=freetype=disable \
	--config-settings=raqm=disable \
	--config-settings=lcms=disable \
	--config-settings=webp=disable \
	--config-settings=jpeg2000=disable \
	--config-settings=imagequant=disable \
	--config-settings=xcb=disable \
	--config-settings=avif=disable

$(STAMP)/packages-moonraker: $(STAMP)/check-toolchain $(STAMP)/crossenv $(STAMP)/libsodium $(REQS_MOONRAKER_BASE) $(REQS_MOONRAKER_PILLOW)
	@echo "==> Cross-compiling Moonraker pip packages..."
	$(CROSSENV_ACTIVATE) \
		build-pip install --quiet --upgrade pip setuptools wheel && \
		build-pip install --quiet pybind11 poetry-core
	$(CROSSENV_ACTIVATE) \
		cross-pip install --quiet pybind11
	$(CROSSENV_ACTIVATE) \
		$(CROSS_ENV_FULL) \
		cross-pip install --no-build-isolation -r $(REQS_MOONRAKER_BASE)
	$(CROSSENV_ACTIVATE) \
		$(CROSS_TOOLCHAIN) \
		CFLAGS="$(CROSS_CFLAGS) -marm -I$(TARGET_PREFIX)/include -I$(VENDOR_SYSROOT)/include" \
		CXXFLAGS="$(CROSS_CXXFLAGS) -marm -I$(TARGET_PREFIX)/include -I$(VENDOR_SYSROOT)/include" \
		CPPFLAGS="-I$(TARGET_PREFIX)/include -I$(VENDOR_SYSROOT)/include -I$(TARGET_PREFIX)/include/python$(PYTHON_MM)" \
		LDFLAGS="$(CROSS_LDFLAGS) -L$(TARGET_PREFIX)/lib -Wl,-Bsymbolic" \
		PKG_CONFIG_LIBDIR="$(TARGET_PREFIX)/lib/pkgconfig:$(VENDOR_SYSROOT)/lib/pkgconfig" \
		PKG_CONFIG_PATH="" \
		PKG_CONFIG_SYSROOT_DIR="$(VENDOR_SYSROOT)" \
		cross-pip install --no-build-isolation $(PILLOW_CONFIG_SETTINGS) \
			$$( $(REQ_STRIP) $(REQS_MOONRAKER) | grep -iE '^[[:space:]]*pillow([^[:alnum:]_.-]|$$)' )
	@touch $@
