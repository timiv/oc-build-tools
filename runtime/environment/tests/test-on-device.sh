#!/bin/sh
# =============================================================================
# test-on-device.sh — Master test runner for /opt/open-centauri on the device
#
# Usage:
#   source /opt/open-centauri/activate
#   sh /opt/open-centauri/tests/test-on-device.sh
#
# Or without activation:
#   sh /opt/open-centauri/tests/test-on-device.sh
# =============================================================================
set -e

OC="/opt/open-centauri"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
SKIP=0
ERRORS=""

# Ensure PATH is set
case ":${PATH}:" in
    *":${OC}/bin:"*) ;;
    *) export PATH="${OC}/bin${PATH:+:$PATH}" ;;
esac
export LD_LIBRARY_PATH="${OC}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

run_test() {
    name="$1"
    shift
    printf "  %-40s " "$name"
    if output=$("$@" 2>&1); then
        PASS=$((PASS + 1))
        echo "OK"
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${name}\n${output}\n"
        echo "FAIL"
    fi
}

# Skip a test with a reason (known limitation)
skip_test() {
    name="$1"
    reason="$2"
    printf "  %-40s SKIP (%s)\n" "$name" "$reason"
    SKIP=$((SKIP + 1))
}

echo "============================================"
echo " Open Centauri Toolchain Tests"
echo "============================================"
echo ""

# --- 1. Basic tools exist ---
echo "[1/6] Basic tool availability"
run_test "python3 in PATH"         which python3
run_test "gcc in PATH"             which gcc
run_test "as (assembler) in PATH"  which as
run_test "ld (linker) in PATH"     which ld
run_test "ar in PATH"              which ar
run_test "strip in PATH"           which strip
echo ""

# --- 2. Python interpreter ---
echo "[2/6] Python interpreter"
run_test "python3 --version"       python3 --version
run_test "python3 -c 'print'"      python3 -c "print('hello from python')"
echo ""

# --- 3. Python imports (kalico) ---
echo "[3/6] Python imports — Kalico dependencies"
run_test "import cffi"             python3 -c "import cffi; print(f'cffi {cffi.__version__}')"
run_test "import _cffi_backend"    python3 -c "import _cffi_backend; print('_cffi_backend OK')"
run_test "import greenlet"         python3 -c "import greenlet; print(f'greenlet {greenlet.__version__}')"
run_test "import jinja2"           python3 -c "import jinja2; print(f'jinja2 {jinja2.__version__}')"
run_test "import markupsafe"       python3 -c "import markupsafe; print(f'markupsafe {markupsafe.__version__}')"
run_test "import numpy"            python3 -c "import numpy; print(f'numpy {numpy.__version__}')"
run_test "import serial"           python3 -c "import serial; print(f'pyserial {serial.__version__}')"
run_test "import can"              python3 -c "import can; print(f'python-can {can.__version__}')"
echo ""

# --- 4. Python imports (moonraker) ---
echo "[4/6] Python imports — Moonraker dependencies"
run_test "import tornado"          python3 -c "import tornado; print(f'tornado {tornado.version}')"
run_test "import PIL"              python3 -c "from PIL import Image; print(f'pillow OK')"
run_test "import streaming_form_data" python3 -c "import streaming_form_data; print('streaming_form_data OK')"
run_test "import distro"           python3 -c "import distro; print(f'distro {distro.__version__}')"
run_test "import inotify_simple"   python3 -c "import inotify_simple; print('inotify_simple OK')"
run_test "import libnacl"          python3 -c "import libnacl; print('libnacl OK')"
run_test "import paho.mqtt"        python3 -c "import paho.mqtt; print('paho-mqtt OK')"
run_test "import zeroconf"         python3 -c "import zeroconf; print(f'zeroconf {zeroconf.__version__}')"
run_test "import preprocess_cancellation" python3 -c "import preprocess_cancellation; print('preprocess_cancellation OK')"
run_test "import dbus_fast"        python3 -c "import dbus_fast; print('dbus_fast OK')"
run_test "import apprise"          python3 -c "import apprise; print(f'apprise {apprise.__version__}')"
run_test "import ldap3"            python3 -c "import ldap3; print(f'ldap3 {ldap3.__version__}')"
run_test "import periphery"        python3 -c "import periphery; print('python-periphery OK')"
run_test "import importlib.metadata" python3 -c "import importlib.metadata; print('importlib.metadata OK')"
echo ""

# --- 5. GCC compile test ---
echo "[5/6] GCC compilation"
run_test "gcc --version"           gcc --version
run_test "gcc -v (config)"         gcc -v

TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

# Simple C program
cat > "$TMPDIR/hello.c" << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
int main(void) {
    printf("hello from gcc on ARM! sqrt(2)=%.6f\n", sqrt(2.0));
    return 0;
}
EOF
run_test "compile hello.c"         gcc -Wall -O2 -o "$TMPDIR/hello" "$TMPDIR/hello.c" -lm
run_test "run hello"               "$TMPDIR/hello"

# Shared library (like chelper does)
cat > "$TMPDIR/shlib.c" << 'EOF'
#include <stdint.h>
int32_t add_values(int32_t a, int32_t b) { return a + b; }
double scale(double x, double factor) { return x * factor; }
EOF
run_test "compile shared lib"      gcc -Wall -O2 -shared -fPIC -o "$TMPDIR/shlib.so" "$TMPDIR/shlib.c"
run_test "load .so from python"    python3 -c "
import ctypes, sys
lib = ctypes.CDLL('$TMPDIR/shlib.so')
lib.add_values.restype = ctypes.c_int32
assert lib.add_values(40, 2) == 42, 'add_values failed'
print('ctypes load + call OK')
"
echo ""

# --- 6. cffi compile test (chelper-style: gcc via os.system + ffi.dlopen) ---
echo "[6/6] CFFI native compilation (chelper-style)"

# This matches exactly how kalico/klippy/chelper/__init__.py works:
#   1. Build shared lib by calling gcc directly (os.system)
#   2. Load it with cffi.FFI().dlopen() — ABI mode, no setuptools needed

cat > "$TMPDIR/chelper_test.c" << 'EOF'
#include <stdint.h>
int32_t multiply(int32_t a, int32_t b) { return a * b; }
double scale(double x, double factor) { return x * factor; }
EOF

run_test "gcc build chelper-style .so" gcc -Wall -g -O2 -shared -fPIC -o "$TMPDIR/chelper_test.so" "$TMPDIR/chelper_test.c"

cat > "$TMPDIR/test_cffi_dlopen.py" << PYEOF
import cffi

ffi = cffi.FFI()
ffi.cdef("""
    int32_t multiply(int32_t a, int32_t b);
    double scale(double x, double factor);
""")

lib = ffi.dlopen("$TMPDIR/chelper_test.so")
r1 = lib.multiply(6, 7)
assert r1 == 42, f"multiply: expected 42, got {r1}"
r2 = lib.scale(3.0, 14.0)
assert abs(r2 - 42.0) < 1e-9, f"scale: expected 42.0, got {r2}"
print(f"cffi dlopen OK (multiply=42, scale=42.0)")
PYEOF
run_test "cffi dlopen + call"      python3 "$TMPDIR/test_cffi_dlopen.py"
echo ""

# --- Summary ---
echo "============================================"
TOTAL=$((PASS + FAIL))
echo " Results: $PASS/$TOTAL passed, $SKIP skipped"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo " Failures:"
    printf "$ERRORS"
    echo ""
    echo " SOME TESTS FAILED"
    echo "============================================"
    exit 1
else
    echo " ALL TESTS PASSED"
    echo "============================================"
    exit 0
fi
