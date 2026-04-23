#!/bin/bash
# Builds tkdnd from source against the Homebrew tcl-tk that python-tk uses.
# Run once after setup.sh:  bash build_tkdnd.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$SCRIPT_DIR/tkdnd_lib"
BUILD="/tmp/tkdnd-build-$$"

# ── 1. Choose Tcl/Tk — prefer 8.6 (stable on macOS 26+) ────────────────────
# Tcl/Tk 9.0 has a crash-on-startup bug on macOS 26+ (empty NSMenuItem title).
# Use tcl-tk@8 if available; fall back to tcl-tk (9.x).
if brew list tcl-tk@8 &>/dev/null 2>&1; then
    TCL_PREFIX="$(brew --prefix tcl-tk@8)"
    echo "==> Using Tcl/Tk 8.6 from $TCL_PREFIX (preferred on macOS 26+)"
elif brew list tcl-tk &>/dev/null 2>&1; then
    TCL_PREFIX="$(brew --prefix tcl-tk)"
    echo "==> Using Tcl/Tk (9.x) from $TCL_PREFIX"
    echo "    NOTE: If RoonTag crashes on startup, run:  brew install tcl-tk@8"
    echo "          Then re-run build_tkdnd.sh and build_app.sh"
else
    echo "==> Installing tcl-tk via Homebrew..."
    brew install tcl-tk
    TCL_PREFIX="$(brew --prefix tcl-tk)"
fi
echo "==> Using Tcl/Tk from $TCL_PREFIX"

# ── 2. Check for Xcode CLT ─────────────────────────────────────────────────
if ! xcode-select -p &>/dev/null; then
    echo "ERROR: Xcode Command Line Tools not installed."
    echo "       Run:  xcode-select --install"
    exit 1
fi

# ── 3. Download tkdnd source (master branch) ───────────────────────────────
echo "==> Downloading tkdnd source..."
mkdir -p "$BUILD"
curl -fsSL \
    "https://github.com/petasis/tkdnd/archive/refs/heads/master.tar.gz" \
    -o "$BUILD/tkdnd.tar.gz"
cd "$BUILD"
tar xf tkdnd.tar.gz
cd tkdnd-master

# ── 4. Configure ───────────────────────────────────────────────────────────
echo "==> Configuring..."
mkdir -p "$OUT"
./configure \
    --with-tcl="$TCL_PREFIX/lib" \
    --with-tk="$TCL_PREFIX/lib" \
    --prefix="$OUT" \
    2>&1 | tail -5

# ── 5. Build ───────────────────────────────────────────────────────────────
echo "==> Building..."
make 2>&1 | tail -10

# ── 6. Copy library manually (make install fails on paths with spaces) ─────
echo "==> Copying library to $OUT ..."
mkdir -p "$OUT/lib"

# Find the built .dylib (might be named libtcl9tkdnd*.dylib or tkdnd*.dylib)
BUILT_LIB=$(find . -maxdepth 1 -name "*.dylib" | head -1)
if [ -z "$BUILT_LIB" ]; then
    echo "ERROR: no .dylib found after make"
    ls -la
    exit 1
fi

LIBNAME=$(basename "$BUILT_LIB")
cp "$BUILT_LIB" "$OUT/lib/$LIBNAME"

# Copy all .tcl library files — required at runtime, especially inside a
# PyInstaller bundle where only the files we copy are available.
for TCL_FILE in *.tcl; do
    [ -f "$TCL_FILE" ] || continue
    [ "$TCL_FILE" = "pkgIndex.tcl" ] && continue   # handled separately below
    cp "$TCL_FILE" "$OUT/lib/$TCL_FILE"
    echo "  Copied $TCL_FILE"
done
# The Tcl library scripts may live in a library/ subdirectory instead
for TCL_FILE in library/*.tcl; do
    [ -f "$TCL_FILE" ] || continue
    BASENAME=$(basename "$TCL_FILE")
    [ "$BASENAME" = "pkgIndex.tcl" ] && continue
    cp "$TCL_FILE" "$OUT/lib/$BASENAME"
    echo "  Copied $BASENAME"
done

# pkgIndex.tcl tells Tcl how to load the package
if [ -f pkgIndex.tcl ]; then
    # Fix the library name in pkgIndex.tcl to match our copy
    sed "s|tkdnd[^ ]*\.dylib|$LIBNAME|g" pkgIndex.tcl > "$OUT/lib/pkgIndex.tcl"
else
    # Generate a minimal pkgIndex.tcl
    TKDND_VERSION=$(echo "$LIBNAME" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    cat > "$OUT/lib/pkgIndex.tcl" <<PKGIDX
if {[catch {load [file join \$dir $LIBNAME]}]} return
package provide tkdnd $TKDND_VERSION
PKGIDX
fi

# ── 7. Verify ──────────────────────────────────────────────────────────────
if [ -f "$OUT/lib/$LIBNAME" ]; then
    echo ""
    echo "✓ tkdnd built: $OUT/lib/$LIBNAME"
    echo ""
    echo "Restart RoonTaggr — drag-and-drop should now work."
else
    echo "ERROR: copy failed"
    exit 1
fi

# ── 8. Clean up build dir ──────────────────────────────────────────────────
cd /tmp
rm -rf "$BUILD"
