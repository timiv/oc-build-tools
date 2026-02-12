# Cross-Compilation Build System for Python ARM Environment

This build system creates a complete Python environment for ARM hard-float targets (Centauri Carbon/Allwinner SoCs with glibc 2.23). It builds GCC 14 from source as a cross-compiler and uses crossenv for pip package cross-compilation.

The vendor toolchain (OpenWrt SDK with glibc 2.23) is automatically downloaded and extracted during the build process.

## Prerequisites

**Ubuntu/Debian:**
```bash
sudo apt install binutils-arm-linux-gnueabihf build-essential curl pkg-config texinfo
```

No external toolchain setup is required—everything is fetched and built automatically.

## Quick Start

```bash
# Build everything and create deployable archive
make

# Or step by step:
make download           # Download all source tarballs
make cross-gcc          # Build GCC 14 cross-compiler (vendor toolchain extracted automatically)
make python-host        # Build host Python (required by crossenv)
make python-target      # Cross-compile target Python
make crossenv           # Set up crossenv
make packages-kalico    # Cross-compile Kalico pip packages
make packages-moonraker # Cross-compile Moonraker pip packages
make zip                # Create archive

# Show all available targets
make help
```

## Setting the Release Version

The archive name defaults to `open-centauri-1.0.0-armhf.tar.gz`. Override the version:

```bash
make VERSION=2.5.1 zip
```

This produces `output/open-centauri-2.5.1-armhf.tar.gz`.

## Build Outputs

- **Source tarballs:** `dl/` (kept across clean cycles)
- **Build artifacts:** `build/` (removed by `make clean`)
- **Final archive:** `output/open-centauri-$(VERSION)-armhf.tar.gz`

## Verification

After building, verify ABI compatibility:

```bash
make verify
```

This checks that all binaries are hard-float and link against glibc ≤ 2.23.

## Vendor Toolchain

The vendor toolchain (OpenWrt SDK for sunxi/Allwinner with glibc 2.23) is included as an archive in the `vendor/` directory. The build system automatically extracts it during the build process.

**Toolchain Details:**
- **Archive:** `vendor/openwrt-toolchain-sunxi-glibc-2.23.tar.gz` (included in repository)
- **GCC Version:** Linaro GCC 6.4-2017.11
- **glibc Version:** 2.23
- **Target:** ARM hard-float ABI (armv7-a + VFPv4)

The toolchain provides the necessary headers, libraries, and runtime components for building GCC 14 and cross-compiling Python packages against glibc 2.23.

## Project Structure

```
python/
├── Makefile                 # Root configuration + top-level targets
├── pkg/                     # Per-package build definitions
│   ├── pkg-macros.mk       # Shared macros and infrastructure
│   ├── host/               # Build machine (x86_64) packages
│   │   ├── vendor-toolchain.mk  # OpenWrt vendor toolchain download/extract
│   │   ├── cross-gcc.mk    # GCC 14 cross-compiler
│   │   └── python.mk       # Host Python (for crossenv)
│   ├── libs/               # Cross-compiled ARM libraries
│   │   ├── zlib.mk
│   │   ├── libffi.mk
│   │   ├── sqlite.mk
│   │   ├── libsodium.mk
│   │   └── openssl.mk
│   ├── toolchain/          # Native ARM toolchain (runs on target)
│   │   ├── binutils.mk
│   │   └── gcc.mk
│   ├── python/             # Target Python ecosystem
│   │   ├── python.mk       # Cross-compiled Python
│   │   └── crossenv.mk     # crossenv setup
│   └── packages/           # Pip packages via crossenv
│       ├── kalico.mk
│       └── moonraker.mk
├── requirements-kalico.txt
├── requirements-moonraker.txt
├── pack-env.sh             # Archive packaging script
└── verify.sh               # ABI verification script
```

## Adding a New Package

### 1. Create a Package File

Drop a new `.mk` file in the appropriate subdirectory under `pkg/`:
- `pkg/host/` — Packages that run on the build machine (x86_64)
- `pkg/libs/` — Cross-compiled libraries for ARM
- `pkg/toolchain/` — Native ARM toolchain components
- `pkg/python/` — Target Python ecosystem components
- `pkg/packages/` — Pip packages

### 2. Define Package Variables

For autotools-based packages (most libraries), use the `autotools-package` macro:

```makefile
# pkg/libs/example.mk
# =============================================================================
# Example library — description here
# =============================================================================
EXAMPLE_VERSION       := 1.2.3
EXAMPLE_URL           := https://example.org/example-$(EXAMPLE_VERSION).tar.gz
EXAMPLE_SRC           := $(SRC_DIR)/example-$(EXAMPLE_VERSION)
EXAMPLE_BUILD_DIR     := $(BUILD_DIR)/example
EXAMPLE_CONFIGURE_ARGS := --prefix=$(TARGET_PREFIX) --enable-shared
EXAMPLE_DEPENDS       := check-toolchain zlib  # Optional dependencies

# Register user-facing target with help text
$(eval $(call user-target,example,\
	Cross-compile example library $(EXAMPLE_VERSION)))

# Register download + extract rule
$(eval $(call download-rule,example,example-$(EXAMPLE_VERSION).tar.gz,$(EXAMPLE_URL),$(EXAMPLE_SRC)))

# Generate build rule (configure/make/make-install)
$(eval $(call autotools-package,EXAMPLE,example))
```

### 3. Custom Build Recipes

For packages that don't use autotools (like OpenSSL or GCC), write a custom stamp recipe:

```makefile
# pkg/libs/custom.mk
CUSTOM_URL := https://example.org/custom.tar.gz
CUSTOM_SRC := $(SRC_DIR)/custom

$(eval $(call user-target,custom,\
	Build custom package with special steps))

$(eval $(call download-rule,custom,custom.tar.gz,$(CUSTOM_URL),$(CUSTOM_SRC)))

$(STAMP)/custom: $(STAMP)/dl-custom | $(CROSS_CC)
	@echo "==> Building custom package..."
	cd $(CUSTOM_SRC) && ./custom-configure --cross-compile
	$(MAKE) -C $(CUSTOM_SRC) CC="$(CROSS_CC)" -j$(JOBS)
	$(MAKE) -C $(CUSTOM_SRC) install PREFIX=$(TARGET_PREFIX)
	@touch $@
```

### 4. That's It!

No need to edit the root `Makefile`! The new package is automatically:
- Included via wildcard: `include $(sort $(wildcard pkg/*/*.mk))`
- Registered in `make download` (via `download-rule`)
- Shown in `make help` (via `user-target`)

## Available Macros

### `user-target`

Declares a user-facing target with automatic help registration:

```makefile
$(eval $(call user-target,target-name,\
	Description text for help output))

# Or with custom stamp name (if target-name ≠ stamp-name):
$(eval $(call user-target,python-host,\
	Build host Python,\
	host-python))
```

Automatically generates:
```makefile
.PHONY: target-name
target-name: $(STAMP)/target-name
```

### `download-rule`

Downloads and extracts a source tarball:

```makefile
$(eval $(call download-rule,stamp-name,tarball-filename,download-url,extracted-src-dir))
```

Example:
```makefile
$(eval $(call download-rule,zlib,zlib-1.3.1.tar.gz,$(ZLIB_URL),$(ZLIB_SRC)))
```

Creates:
- `$(STAMP)/dl-zlib` target
- Downloads to `dl/zlib-1.3.1.tar.gz`
- Extracts to `src/zlib-1.3.1`
- Auto-registers in `make download`

### `autotools-package`

Standard configure/make/install for cross-compiled libraries:

```makefile
$(eval $(call autotools-package,UPPERCASE_PREFIX,stamp-name))
```

Requires these variables to be set:
- `UPPERCASE_PREFIX_VERSION` — For log messages
- `UPPERCASE_PREFIX_SRC` — Source directory path
- `UPPERCASE_PREFIX_BUILD_DIR` — Out-of-tree build directory
- `UPPERCASE_PREFIX_CONFIGURE_ARGS` — Arguments for ./configure
- `UPPERCASE_PREFIX_DEPENDS` — Space-separated list of stamp dependencies (optional)

Example:
```makefile
ZLIB_VERSION       := 1.3.1
ZLIB_SRC           := $(SRC_DIR)/zlib-1.3.1
ZLIB_BUILD_DIR     := $(BUILD_DIR)/zlib
ZLIB_CONFIGURE_ARGS := --prefix=$(TARGET_PREFIX)
ZLIB_DEPENDS       := check-toolchain

$(eval $(call autotools-package,ZLIB,zlib))
```

## Cross-Compilation Environment

The build system provides these environment variable helpers for cross-compilation:

- **`CROSS_TOOLCHAIN`** — Just CC/CXX/AR/RANLIB
- **`CROSS_ENV`** — Adds CFLAGS/CXXFLAGS/LDFLAGS
- **`CROSS_ENV_FULL`** — Full environment with all include/lib paths

Example usage in custom recipes:
```makefile
cd $(BUILD_DIR) && \
	$(CROSS_ENV) \
	./configure --host=$(CROSS_HOST)
```

## Important Notes

### Stamp Files

All build steps use stamp files under `build/.stamps/` to track completion. The stamp filename should match the primary purpose (e.g., `host-python`, `zlib`, `crossenv`). Delete stamps to force rebuilds:

```bash
rm build/.stamps/zlib    # Rebuild only zlib
rm -rf build/.stamps/    # Rebuild everything
```

### Package Versions

All version numbers are centralized in the root `Makefile` (lines 40-49). Update them in one place:

```makefile
PYTHON_VERSION     := 3.13.11
LIBFFI_VERSION     := 3.4.7
ZLIB_VERSION       := 1.3.1
# ... etc
```

### Parallel Builds

The default is `JOBS ?= 8`. Override with:

```bash
make JOBS=16
```

### Incremental Builds

The build system respects existing stamps. If you modify a package's `.mk` file, remove its stamp to force a rebuild:

```bash
rm build/.stamps/packages-kalico  # Rebuild kalico packages only
```

### Python Packages (crossenv)

For pip packages cross-compiled via crossenv, see `pkg/packages/kalico.mk` and `pkg/packages/moonraker.mk` as examples. Special handling is often needed for packages with native extensions (numpy uses meson, Pillow needs config-settings).

### Target Architecture

Currently hardcoded for **ARM Cortex-A7, VFPv4+NEON, hard-float ABI**. Edit these lines in the root `Makefile` to target a different ARM variant:

```makefile
CROSS_HOST := arm-linux-gnueabihf
ARCH_FLAGS := -march=armv7-a -mfpu=vfpv4 -mfloat-abi=hard
```

## Troubleshooting

**Q: Build fails with "cannot find -lc"**
A: The vendor sysroot is missing or misconfigured. Check `VENDOR_SYSROOT` path in `Makefile`.

**Q: Python packages fail to import on target**
A: Run `make verify` to check glibc compatibility. The target device must have glibc ≤ 2.23.

**Q: GCC build takes forever**
A: GCC compilation takes 15-30 minutes on a typical machine. The stamp prevents rebuilds. If interrupted, remove `build/.stamps/cross-gcc` to retry cleanly.

**Q: How do I add a new pip package?**
A: Add it to `requirements-kalico.txt` or `requirements-moonraker.txt`, then rebuild:
```bash
rm build/.stamps/packages-kalico
make packages-kalico
```

**Q: Download fails with 404**
A: Update the version number and URL in the relevant `.mk` file under `pkg/`.

## License

See parent project for license information.
