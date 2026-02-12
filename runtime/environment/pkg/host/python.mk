# =============================================================================
# Host Python — same version as target, required by crossenv
# =============================================================================
PYTHON_URL  := https://www.python.org/ftp/python/$(PYTHON_VERSION)/Python-$(PYTHON_VERSION).tar.xz
CPYTHON_SRC := $(SRC_DIR)/Python-$(PYTHON_VERSION)

HOST_BUILD := $(BUILD_DIR)/build/python-host

$(eval $(call user-target,python-host,\
	Build host Python $(PYTHON_VERSION) (required by crossenv),\
	host-python))

# Download rule is shared with python-target (same tarball).
$(eval $(call download-rule,python,Python-$(PYTHON_VERSION).tar.xz,$(PYTHON_URL),$(CPYTHON_SRC)))

$(STAMP)/host-python: $(STAMP)/dl-python
	@echo "==> Building host Python $(PYTHON_VERSION)..."
	@mkdir -p $(HOST_BUILD) $(STAMP)
	cd $(HOST_BUILD) && \
		$(CPYTHON_SRC)/configure \
			--prefix=$(HOST_PREFIX) \
			--disable-test-modules --without-static-libpython \
			--with-ensurepip=install
	$(MAKE) -C $(HOST_BUILD) -j$(JOBS)
	$(MAKE) -C $(HOST_BUILD) install
	$(HOST_PREFIX)/bin/python$(PYTHON_MM) --version
	@touch $@
