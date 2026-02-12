# =============================================================================
# SQLite3 — provides _sqlite3 module for Python
# =============================================================================
SQLITE_URL            := https://www.sqlite.org/2024/sqlite-autoconf-$(SQLITE_VERSION).tar.gz
SQLITE_SRC            := $(SRC_DIR)/sqlite-autoconf-$(SQLITE_VERSION)
SQLITE_BUILD_DIR      := $(BUILD_DIR)/sqlite
SQLITE_CONFIGURE_ARGS := \
	--host=$(CROSS_HOST) \
	--prefix=$(TARGET_PREFIX) \
	--disable-static --enable-shared
SQLITE_DEPENDS        := check-toolchain

.PHONY: sqlite
sqlite: $(STAMP)/sqlite

$(eval $(call download-rule,sqlite,sqlite-autoconf-$(SQLITE_VERSION).tar.gz,$(SQLITE_URL),$(SQLITE_SRC)))
$(eval $(call autotools-package,SQLITE,sqlite))
