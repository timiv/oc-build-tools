# =============================================================================
# Kalico pip packages — cross-compiled via crossenv
# =============================================================================
$(eval $(call user-target,packages-kalico,\
	Cross-compile Kalico pip packages (numpy etc)))

# Split requirements: numpy needs special build flags
REQS_KALICO_BASE  := $(BUILD_DIR)/requirements-kalico-base.txt
REQS_KALICO_NUMPY := $(BUILD_DIR)/requirements-kalico-numpy.txt

$(REQS_KALICO_BASE): $(REQS_KALICO) | $(BUILD_DIR)
	@echo "==> Generating $(notdir $@)..."
	@$(REQ_STRIP) $< | grep -ivE '^[[:space:]]*numpy([^[:alnum:]_.-]|$$)' > $@

$(REQS_KALICO_NUMPY): $(REQS_KALICO) | $(BUILD_DIR)
	@echo "==> Generating $(notdir $@)..."
	@$(REQ_STRIP) $< | grep -iE '^[[:space:]]*numpy([^[:alnum:]_.-]|$$)' > $@

$(STAMP)/packages-kalico: $(STAMP)/check-toolchain $(STAMP)/crossenv $(REQS_KALICO_BASE) $(REQS_KALICO_NUMPY) $(MESON_CROSS)
	@echo "==> Cross-compiling Kalico pip packages..."
	$(CROSSENV_ACTIVATE) \
		build-pip install --quiet --upgrade pip setuptools wheel && \
		build-pip install --quiet pycparser cython 'meson-python>=0.16' meson
	@# Non-numpy packages
	$(CROSSENV_ACTIVATE) \
		$(CROSS_ENV_FULL) \
		cross-pip install --no-build-isolation -r $(REQS_KALICO_BASE)
	@# numpy (needs meson cross-file + cython on PATH)
	$(CROSSENV_ACTIVATE) \
		export PATH="$(CROSSENV_DIR)/build/bin:$$PATH" && \
		$(CROSS_ENV) \
		cross-pip install --no-build-isolation --no-cache-dir \
			--config-settings=setup-args="-Dallow-noblas=true" \
			--config-settings=setup-args="--cross-file=$(MESON_CROSS)" \
			$$( $(REQ_STRIP) $(REQS_KALICO) | grep -iE '^[[:space:]]*numpy([^[:alnum:]_.-]|$$)' )
	@touch $@
