# =============================================================================
# crossenv — pip cross-compilation environment
# =============================================================================
$(eval $(call user-target,crossenv,\
	Set up crossenv for pip cross-compilation))

$(STAMP)/crossenv: $(STAMP)/target-python | $(CROSS_CC) $(CROSS_CXX)
	@echo "==> Setting up crossenv..."
	$(HOST_PREFIX)/bin/python$(PYTHON_MM) -m pip install --quiet crossenv
	$(HOST_PREFIX)/bin/python$(PYTHON_MM) -m crossenv \
		$(TARGET_PREFIX)/bin/python$(PYTHON_MM) $(CROSSENV_DIR) \
		--cc "$(CROSS_CC)" --cxx "$(CROSS_CXX)" --ar "$(CROSS_AR)"
	@echo "==> crossenv created at $(CROSSENV_DIR)"
	@touch $@
