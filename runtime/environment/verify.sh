#!/usr/bin/env bash
# =============================================================================
# verify.sh — Verify all cross-compiled ELF binaries are hard-float and
#              compatible with glibc ≤ 2.23.
#
# Usage (called by the Makefile):
#   bash verify.sh <dir> [<dir> ...]
#
# Scans all ELF files (.so and executables) under the given directories.
# =============================================================================
set -euo pipefail

MAX_GLIBC="2.23"
FAIL=0

# Collect all ELF files from arguments
FILES=()
for dir in "$@"; do
    while IFS= read -r -d '' f; do
        FILES+=("$f")
    done < <(find "$dir" \( -name '*.so' -o -name '*.so.*' -o -type f -executable \) -print0 2>/dev/null)
done

for f in "${FILES[@]}"; do
    # Skip non-ELF
    file -b "$f" | grep -q 'ELF' || continue

    # Check 1: hard-float ABI
    if readelf -h "$f" 2>/dev/null | grep -q "soft-float"; then
        echo "  FAIL (soft-float): $f"
        FAIL=1
    fi

    # Check 2: glibc version requirement
    MAX_VER=$(readelf -V "$f" 2>/dev/null \
        | grep -oP 'GLIBC_\K[0-9.]+' \
        | sort -V | tail -1) || true
    if [[ -n "$MAX_VER" ]]; then
        HIGHEST=$(printf '%s\n' "$MAX_GLIBC" "$MAX_VER" | sort -V | tail -1)
        if [[ "$HIGHEST" != "$MAX_GLIBC" ]]; then
            echo "  FAIL (GLIBC_$MAX_VER > $MAX_GLIBC): $f"
            FAIL=1
        fi
    fi
done

if [[ $FAIL -eq 0 ]]; then
    echo "==> All ${#FILES[@]} binaries: hard-float, glibc ≤ $MAX_GLIBC. OK."
else
    echo "==> ERROR: Some binaries failed verification!"
    exit 1
fi
