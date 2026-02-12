#!/usr/bin/env bash
# =============================================================================
# pack-env.sh — Package cross-compiled Python + native gcc toolchain into a
#               single deployable .tar.gz archive.
#
# Deploy on device:  tar xzf <archive> -C /
# Prefix on device:  /opt/open-centauri
# Activate:          source /opt/open-centauri/activate
#
# Layout inside archive:
#   opt/open-centauri/
#     activate       — shell snippet: sets PATH + LD_LIBRARY_PATH
#     bin/           — python3, python3.XX, gcc, as, ld, ar, …
#     lib/           — shared libs, gcc internal libs
#       python3.XX/  — stdlib + site-packages
#       gcc/         — gcc internal libraries (specs, crt*.o, …)
#     libexec/
#       gcc/         — cc1, collect2, lto-wrapper
#     include/       — binutils/gcc plugin headers
#
# Usage (called by the Makefile):
#   bash pack-env.sh \
#       --target-prefix BUILD/staging/python-target \
#       --crossenv      BUILD/staging/crossenv \
#       --python-version 3.13 \
#       --sysroot-lib    VENDOR_SYSROOT/lib \
#       --cross-gcc-lib  BUILD/staging/gcc-cross/arm-linux-gnueabihf/lib \
#       --gcc-prefix     BUILD/staging/gcc-native/opt/open-centauri \
#       --output         output/open-centauri-armhf.tar.gz
# =============================================================================
set -euo pipefail

TARGET_PREFIX=""
CROSSENV_DIR=""
PYVER=""
SYSROOT_LIB=""
CROSS_GCC_LIB=""
GCC_PREFIX=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-prefix)   TARGET_PREFIX="$2"; shift 2;;
        --crossenv)        CROSSENV_DIR="$2"; shift 2;;
        --python-version)  PYVER="$2"; shift 2;;
        --sysroot-lib)     SYSROOT_LIB="$2"; shift 2;;
        --cross-gcc-lib)   CROSS_GCC_LIB="$2"; shift 2;;
        --gcc-prefix)      GCC_PREFIX="$2"; shift 2;;
        --output)          OUTPUT="$2"; shift 2;;
        *) echo "Unknown argument: $1"; exit 1;;
    esac
done

for v in TARGET_PREFIX CROSSENV_DIR PYVER SYSROOT_LIB CROSS_GCC_LIB GCC_PREFIX OUTPUT; do
    if [[ -z "${!v}" ]]; then
        echo "Missing required argument: --$(echo $v | tr '_A-Z' '-a-z')"
        exit 1
    fi
done

STAGING=$(mktemp -d)
trap "rm -rf '$STAGING'" EXIT

DEST="$STAGING/opt/open-centauri"
PYBIN="python${PYVER}"

# ---- Native gcc/binutils toolchain (first, so Python overwrites nothing) -----
echo "==> Staging native gcc/binutils toolchain..."
if [[ -d "$GCC_PREFIX/bin" ]]; then
    # Copy entire prefix tree — bin/, lib/, libexec/, include/
    mkdir -p "$DEST"
    cp -a "$GCC_PREFIX/." "$DEST/"

    # Strip debug symbols to reduce archive size
    find "$DEST" -type f \( -executable -o -name '*.a' -o -name '*.o' \) -print0 | \
        while IFS= read -r -d '' f; do
            if file -b "$f" | grep -q 'ELF.*ARM'; then
                arm-linux-gnueabihf-strip --strip-debug "$f" 2>/dev/null || true
            fi
        done

    # Remove unnecessary files from gcc prefix
    rm -rf "$DEST/share/man" "$DEST/share/info" 2>/dev/null || true
    rm -rf "$DEST/include" 2>/dev/null || true
    rm -f "$DEST/lib/libbfd.a" "$DEST/lib/libopcodes.a" 2>/dev/null || true

    GCC_BIN_COUNT=$(find "$DEST/bin" -type f | wc -l)
    echo "    $GCC_BIN_COUNT binaries staged"
else
    echo "ERROR: gcc-prefix not found: $GCC_PREFIX"
    exit 1
fi

# ---- Python interpreter -----------------------------------------------------
echo "==> Staging Python interpreter..."
mkdir -p "$DEST/bin"
cp "$TARGET_PREFIX/bin/$PYBIN" "$DEST/bin/"

# Set RPATH so the dynamic linker finds our bundled libs without LD_LIBRARY_PATH
echo "==> Patching Python RPATH..."
patchelf --set-rpath '$ORIGIN/../lib' "$DEST/bin/$PYBIN"

# ---- Python stdlib -----------------------------------------------------------
echo "==> Staging Python stdlib..."
STDLIB_SRC="$TARGET_PREFIX/lib/$PYBIN"
mkdir -p "$DEST/lib/$PYBIN"
rsync -a --exclude='__pycache__' --exclude='test' --exclude='tests' \
    --exclude='tkinter' --exclude='turtle*' --exclude='idlelib' \
    --exclude='ensurepip' --exclude='config-*/libpython*.a' \
    "$STDLIB_SRC/" "$DEST/lib/$PYBIN/"

# ---- lib-dynload -------------------------------------------------------------
echo "==> Staging lib-dynload..."
mkdir -p "$DEST/lib/$PYBIN/lib-dynload"
if [[ -d "$TARGET_PREFIX/lib/$PYBIN/lib-dynload" ]]; then
    cp -a "$TARGET_PREFIX/lib/$PYBIN/lib-dynload/"*.so "$DEST/lib/$PYBIN/lib-dynload/" 2>/dev/null || true
fi

# ---- site-packages -----------------------------------------------------------
echo "==> Staging site-packages..."
SITE_SRC="$CROSSENV_DIR/cross/lib/$PYBIN/site-packages"
if [[ -d "$SITE_SRC" ]]; then
    mkdir -p "$DEST/lib/$PYBIN/site-packages"
    rsync -a --exclude='__pycache__' --exclude='*.pyc' \
        --exclude='pip' --exclude='pip-*' \
        --exclude='wheel' --exclude='wheel-*' \
        --exclude='pkg_resources' \
        "$SITE_SRC/" "$DEST/lib/$PYBIN/site-packages/"
fi

# ---- Compile Python files to bytecode ---------------------------------------
echo "==> Compiling Python files to bytecode..."
HOST_PYTHON_DIR="${TARGET_PREFIX/python-target/python-host}"
HOST_PYTHON="$HOST_PYTHON_DIR/bin/$PYBIN"

if [[ -x "$HOST_PYTHON" ]]; then
    # Compile all Python files in stdlib and site-packages
    "$HOST_PYTHON" -m compileall -q -j 0 "$DEST/lib/$PYBIN" 2>/dev/null || true

    # Move .pyc from __pycache__/module.cpython-XXX.pyc → module.pyc
    # Python can import sourceless .pyc only when they sit directly in the
    # module directory (not inside __pycache__/ which is just a cache).
    PYCTAG="cpython-${PYVER//./}"
    find "$DEST/lib/$PYBIN" -path '*/__pycache__/*.pyc' -print0 | while IFS= read -r -d '' pyc; do
        base=$(basename "$pyc")                          # e.g. os.cpython-313.pyc
        mod_name="${base%.${PYCTAG}.pyc}.pyc"            # e.g. os.pyc
        parent=$(dirname "$(dirname "$pyc")")            # e.g. .../lib/python3.13
        mv -f "$pyc" "$parent/$mod_name"
    done

    # Remove now-empty __pycache__ directories and .py source files
    find "$DEST/lib/$PYBIN" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
    find "$DEST/lib/$PYBIN" -type f -name '*.py' -delete

    PYC_COUNT=$(find "$DEST/lib/$PYBIN" -name '*.pyc' | wc -l)
    echo "    $PYC_COUNT .pyc files generated, all .py sources removed"
else
    echo "WARN: Host Python not found at $HOST_PYTHON, skipping bytecode generation"
fi

# ---- Shared libraries --------------------------------------------------------
echo "==> Staging shared libraries..."
mkdir -p "$DEST/lib"

# All .so libraries from our target-prefix (libffi, zlib, OpenSSL, SQLite,
# libsodium, and anything new added via pkg/libs/*.mk — no need to list
# individual library names here).
find "$TARGET_PREFIX/lib" -maxdepth 1 -name '*.so*' -exec cp -aL {} "$DEST/lib/" \;
LIB_COUNT=$(find "$DEST/lib" -maxdepth 1 -name '*.so*' | wc -l)
echo "    $LIB_COUNT shared libraries staged from target-prefix"

# libgcc_s and libstdc++ from cross-GCC 14 (built against glibc 2.23)
# These are newer than the vendor's but still compatible with the target glibc.
if [[ -f "$CROSS_GCC_LIB/libgcc_s.so.1" ]]; then
    cp -a "$CROSS_GCC_LIB/libgcc_s.so.1" "$DEST/lib/"
elif [[ -f "$SYSROOT_LIB/libgcc_s.so.1" ]]; then
    cp -a "$SYSROOT_LIB/libgcc_s.so.1" "$DEST/lib/"
fi
if [[ -f "$CROSS_GCC_LIB/libstdc++.so.6" ]]; then
    cp -aL "$CROSS_GCC_LIB/libstdc++.so.6" "$DEST/lib/"
    # Also copy the versioned .so.6.0.XX file if present
    for f in "$CROSS_GCC_LIB/"/libstdc++.so.6.*; do
        [[ -f "$f" ]] && cp -aL "$f" "$DEST/lib/"
    done
elif [[ -f "$SYSROOT_LIB/libstdc++.so.6" ]]; then
    cp -aL "$SYSROOT_LIB/libstdc++.so.6" "$DEST/lib/"
fi
# Use -L to dereference symlinks (libutil.so.1 → libutil-2.23.so)
for lib in libutil.so.1 libutil-2.23.so libatomic.so.1; do
    [[ -e "$SYSROOT_LIB/$lib" ]] && cp -aL "$SYSROOT_LIB/$lib" "$DEST/lib/"
done

# ---- GCC sysroot (headers + CRT for on-device compilation) ------------------
echo "==> Staging GCC sysroot (glibc headers + CRT)..."
SYSROOT_INCLUDE="$(dirname "$SYSROOT_LIB")/include"
GCC_SYSROOT="$DEST/arm-linux-gnueabihf/sysroot"
if [[ -d "$SYSROOT_INCLUDE" ]]; then
    # Glibc headers
    mkdir -p "$GCC_SYSROOT/usr/include"
    cp -a "$SYSROOT_INCLUDE/." "$GCC_SYSROOT/usr/include/"

    # CRT object files (needed for linking executables and shared libs)
    mkdir -p "$GCC_SYSROOT/usr/lib"
    for f in crt1.o crti.o crtn.o Scrt1.o; do
        [[ -f "$SYSROOT_LIB/$f" ]] && cp -a "$SYSROOT_LIB/$f" "$GCC_SYSROOT/usr/lib/"
    done

    # Linker scripts and stubs (libc.so, libpthread.so reference .so.X on device)
    for f in libc.so libc_nonshared.a libpthread.so libpthread_nonshared.a; do
        [[ -f "$SYSROOT_LIB/$f" ]] && cp -a "$SYSROOT_LIB/$f" "$GCC_SYSROOT/usr/lib/"
    done

    # Create linker scripts for libs that are symlinks in the sysroot
    # (the device has .so.X in /lib/ but no development .so in /usr/lib/)
    for pair in "m:libm.so.6" "dl:libdl.so.2" "rt:librt.so.1" "util:libutil.so.1"; do
        name="${pair%%:*}"
        target="${pair#*:}"
        cat > "$GCC_SYSROOT/usr/lib/lib${name}.so" << EOF
/* GNU ld script */
GROUP ( $target )
EOF
    done

    HDR_COUNT=$(find "$GCC_SYSROOT/usr/include" -type f | wc -l)
    echo "    $HDR_COUNT header files staged"
else
    echo "WARN: sysroot include dir not found: $SYSROOT_INCLUDE"
fi

# ---- GCC runtime objects (crtbegin, crtend, libgcc — from vendor toolchain) ---
echo "==> Staging GCC runtime objects..."
GCC_SPECS_DIR=$(find "$DEST/lib/gcc" -maxdepth 2 -name '6.*' -type d 2>/dev/null | head -1)
VENDOR_GCC_LIB=$(find "$(dirname "$SYSROOT_LIB")/lib/gcc" -maxdepth 2 -name '6.*' -type d 2>/dev/null | head -1)
if [[ -n "$VENDOR_GCC_LIB" && -n "$GCC_SPECS_DIR" ]]; then
    for f in crtbegin.o crtbeginS.o crtbeginT.o crtend.o crtendS.o crtfastmath.o \
             libgcc.a libgcc_eh.a; do
        [[ -f "$VENDOR_GCC_LIB/$f" ]] && cp -a "$VENDOR_GCC_LIB/$f" "$GCC_SPECS_DIR/"
    done
    # Also copy glibc CRT here — gcc searches its own version dir before sysroot
    for f in crt1.o crti.o crtn.o Scrt1.o; do
        [[ -f "$SYSROOT_LIB/$f" ]] && cp -a "$SYSROOT_LIB/$f" "$GCC_SPECS_DIR/"
    done
    echo "    GCC runtime objects staged from vendor toolchain"
else
    echo "WARN: could not find vendor gcc lib dir for runtime objects"
fi

# ---- GCC specs file (tells gcc where to find headers and CRT) ----------------
echo "==> Generating GCC specs file..."
if [[ -n "$GCC_SPECS_DIR" ]]; then
    cat > "$GCC_SPECS_DIR/specs" << 'SPECS'
*cc1:
+ -isystem /opt/open-centauri/arm-linux-gnueabihf/sysroot/usr/include

*link:
+ -L/opt/open-centauri/arm-linux-gnueabihf/sysroot/usr/lib --sysroot=/opt/open-centauri/arm-linux-gnueabihf/sysroot
SPECS
    echo "    specs written to ${GCC_SPECS_DIR#$STAGING/}/specs"
else
    echo "WARN: could not find gcc version dir for specs file"
fi

# ---- Launcher scripts --------------------------------------------------------
echo "==> Staging launcher scripts..."

# python3 → python3.XX wrapper with LD_LIBRARY_PATH
cat > "$DEST/bin/python3" << 'LAUNCHER'
#!/bin/sh
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONHOME="$DIR"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$DIR/bin/PYBIN_PLACEHOLDER" "$@"
LAUNCHER
sed -i "s/PYBIN_PLACEHOLDER/$PYBIN/" "$DEST/bin/python3"
chmod +x "$DEST/bin/python3"

# ---- Activation script -------------------------------------------------------
echo "==> Staging activation script..."
cat > "$DEST/activate" << 'ACTIVATE'
# Source this file:  . /opt/open-centauri/activate
#
# Adds /opt/open-centauri/bin to PATH and sets LD_LIBRARY_PATH so that
# Python, gcc, binutils and all bundled shared libraries are available.

_OC_PREFIX="/opt/open-centauri"

# Avoid double-activation
case ":${PATH}:" in
    *":${_OC_PREFIX}/bin:"*) ;;
    *) export PATH="${_OC_PREFIX}/bin${PATH:+:$PATH}" ;;
esac

export PYTHONHOME="${_OC_PREFIX}"

case ":${LD_LIBRARY_PATH-}:" in
    *":${_OC_PREFIX}/lib:"*) ;;
    *) export LD_LIBRARY_PATH="${_OC_PREFIX}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
esac

echo "open-centauri environment activated (${_OC_PREFIX})"
echo "  python3 $(python3 --version 2>&1 | awk '{print $2}' 2>/dev/null || echo '?')"
echo "  gcc     $(gcc --version 2>/dev/null | head -1 | grep -oP '[\d.]+$' || echo '?')"

unset _OC_PREFIX
ACTIVATE

# ---- Test scripts ------------------------------------------------------------
echo "==> Staging test scripts..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$SCRIPT_DIR/tests" ]]; then
    mkdir -p "$DEST/tests"
    cp "$SCRIPT_DIR/tests/"*.sh "$DEST/tests/"
    chmod +x "$DEST/tests/"*.sh
fi

# ---- Create archive ----------------------------------------------------------
echo "==> Creating archive..."
mkdir -p "$(dirname "$OUTPUT")"
tar czf "$OUTPUT" -C "$STAGING" opt/open-centauri

FILE_COUNT=$(tar tzf "$OUTPUT" | wc -l)
echo "==> Done: $OUTPUT ($(du -h "$OUTPUT" | cut -f1), $FILE_COUNT files)"
