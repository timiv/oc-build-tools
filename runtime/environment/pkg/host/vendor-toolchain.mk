# =============================================================================
# vendor-toolchain.mk — Download and extract OpenWrt vendor toolchain
#
# This provides the glibc 2.23 sysroot against which we build GCC 14.
# The toolchain archive is included in the vendor/ directory.
# =============================================================================

VENDOR_TOOLCHAIN_EXTRACT_DIR := $(BUILD_DIR)/vendor-toolchain
VENDOR_TOOLCHAIN_LOCAL := $(VENDOR_DIR)/$(VENDOR_TOOLCHAIN_ARCHIVE)

# Check for vendor toolchain archive
$(STAMP)/dl-vendor-toolchain:
	@echo "==> Checking for vendor toolchain archive..."
	@mkdir -p $(DL_DIR) $(STAMP)
	@if [ ! -f "$(VENDOR_TOOLCHAIN_LOCAL)" ]; then \
		echo "ERROR: Vendor toolchain archive not found: $(VENDOR_TOOLCHAIN_LOCAL)"; \
		echo "       This file should be included in the repository."; \
		echo "       Archive contains: OpenWrt SDK (Linaro GCC 6.4-2017.11, glibc 2.23)"; \
		exit 1; \
	fi
	@echo "    Found: $(VENDOR_TOOLCHAIN_LOCAL)"
	@touch $@

# Extract vendor toolchain
$(STAMP)/vendor-toolchain: $(STAMP)/dl-vendor-toolchain
	@echo "==> Extracting vendor toolchain..."
	@rm -rf $(VENDOR_TOOLCHAIN_EXTRACT_DIR)
	@mkdir -p $(VENDOR_TOOLCHAIN_EXTRACT_DIR)
	$(TAR) xzf $(VENDOR_TOOLCHAIN_LOCAL) -C $(VENDOR_TOOLCHAIN_EXTRACT_DIR)
	@echo "    Extracted to: $(VENDOR_SYSROOT)"
	@touch $@

# Register download
ALL_DOWNLOADS += $(STAMP)/dl-vendor-toolchain

$(eval $(call user-target,vendor-toolchain,Download and extract vendor toolchain))
