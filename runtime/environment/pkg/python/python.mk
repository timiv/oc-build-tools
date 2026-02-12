# =============================================================================
# Target Python — cross-compiled for ARM hard-float
# =============================================================================
TARGET_BUILD := $(BUILD_DIR)/build/python-target

$(eval $(call user-target,python-target,\
	Cross-compile Python $(PYTHON_VERSION) for ARM target,\
	target-python))

$(STAMP)/target-python: $(STAMP)/check-toolchain $(STAMP)/host-python $(STAMP)/libffi $(STAMP)/zlib $(STAMP)/openssl $(STAMP)/sqlite | $(CROSS_CC) $(CROSS_CXX)
	@echo "==> Cross-compiling Python $(PYTHON_VERSION) for ARM hard-float..."
	@mkdir -p $(TARGET_BUILD) $(STAMP)
	cd $(TARGET_BUILD) && \
		$(CROSS_TOOLCHAIN) \
		CFLAGS="$(CROSS_CFLAGS) -I$(TARGET_PREFIX)/include" \
		CPPFLAGS="-I$(TARGET_PREFIX)/include" \
		LDFLAGS="$(CROSS_LDFLAGS) -L$(TARGET_PREFIX)/lib -Wl,-rpath-link,$(TARGET_PREFIX)/lib" \
		PKG_CONFIG_LIBDIR="$(TARGET_PREFIX)/lib/pkgconfig" \
		$(CPYTHON_SRC)/configure \
			--prefix=$(TARGET_PREFIX) \
			--host=$(CROSS_HOST) \
			--build=$(BUILD_TRIPLET) \
			--with-build-python=$(HOST_PREFIX)/bin/python$(PYTHON_MM) \
			--with-openssl=$(TARGET_PREFIX) \
			--disable-ipv6 --disable-test-modules --with-ensurepip=no \
			ac_cv_file__dev_ptmx=yes ac_cv_file__dev_ptc=no
	$(MAKE) -C $(TARGET_BUILD) -j$(JOBS)
	$(MAKE) -C $(TARGET_BUILD) install
	@readelf -h $(TARGET_PREFIX)/bin/python$(PYTHON_MM) | grep -q "hard-float" \
		|| { echo "ERROR: target Python is not hard-float!"; exit 1; }
	@echo "==> Target Python: hard-float ABI confirmed"
	@touch $@
