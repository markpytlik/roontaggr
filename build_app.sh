#!/bin/bash
# Builds a self-contained RoonTag.app using PyInstaller.
# Prerequisites: run setup.sh and build_tkdnd.sh first.
# Usage: bash build_app.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$SCRIPT_DIR/venv"
PY="$VENV/bin/python3"
DIST="$SCRIPT_DIR/dist"

# ── Read version (single source of truth) ───────────────────────────────────
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
else
    VERSION="dev"
fi
echo "==> Building RoonTag v$VERSION"

# ── 1. Install / upgrade PyInstaller ────────────────────────────────────────
echo "==> Installing PyInstaller…"
"$VENV/bin/pip" install --quiet --upgrade pyinstaller

# ── 2. Verify tkdnd_lib is present ──────────────────────────────────────────
if [ ! -d "$SCRIPT_DIR/tkdnd_lib/lib" ]; then
    echo "ERROR: tkdnd_lib not found. Run build_tkdnd.sh first."
    exit 1
fi

# ── 3. Patch tkdnd dylib to use @loader_path so it works inside the bundle ───
echo "==> Patching tkdnd library for bundle compatibility…"
TKDND_DYLIB=$(ls "$SCRIPT_DIR/tkdnd_lib/lib/"*.dylib 2>/dev/null | head -1)
if [ -z "$TKDND_DYLIB" ]; then
    echo "ERROR: no .dylib found in tkdnd_lib/lib/. Run build_tkdnd.sh first."
    exit 1
fi

# For each external dependency of the tkdnd dylib, copy it into tkdnd_lib/lib/
# and rewrite the reference to @loader_path so it's found inside the bundle.
while IFS= read -r dep; do
    # Skip self-references and system libs
    [[ "$dep" == "$TKDND_DYLIB" ]] && continue
    [[ "$dep" == /usr/lib/* ]]      && continue
    [[ "$dep" == /System/* ]]       && continue
    [[ "$dep" == @* ]]              && continue
    depname=$(basename "$dep")
    destlib="$SCRIPT_DIR/tkdnd_lib/lib/$depname"
    if [ ! -f "$destlib" ]; then
        echo "  Copying $depname"
        cp "$dep" "$destlib"
        # Allow writing (Homebrew dylibs are read-only)
        chmod u+w "$destlib"
    fi
    echo "  Patching reference: $dep → @loader_path/$depname"
    install_name_tool -change "$dep" "@loader_path/$depname" "$TKDND_DYLIB"
done < <(otool -L "$TKDND_DYLIB" | tail -n +2 | awk '{print $1}')

# Also patch install name of the dylib itself
LIBNAME=$(basename "$TKDND_DYLIB")
install_name_tool -id "@loader_path/$LIBNAME" "$TKDND_DYLIB" 2>/dev/null || true

# ── 4. Write .spec file ──────────────────────────────────────────────────────
echo "==> Writing RoonTag.spec…"
ICNS_ARG="None"
if [ -f "$SCRIPT_DIR/RoonTag.icns" ]; then
    ICNS_ARG="'$SCRIPT_DIR/RoonTag.icns'"
fi

cat > "$SCRIPT_DIR/RoonTag.spec" << SPECEOF
# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path
SCRIPT_DIR = Path(r'$SCRIPT_DIR')

a = Analysis(
    [str(SCRIPT_DIR / 'app.py')],
    pathex=[str(SCRIPT_DIR)],
    binaries=[],
    datas=[
        (str(SCRIPT_DIR / 'tkdnd_lib'), 'tkdnd_lib'),
        (str(SCRIPT_DIR / 'VERSION'), '.'),
        (str(SCRIPT_DIR / 'CHANGELOG.md'), '.'),
    ],
    hiddenimports=[
        'mutagen', 'mutagen.mp3', 'mutagen.flac', 'mutagen.aiff',
        'mutagen.mp4', 'mutagen.wave', 'mutagen.id3', 'mutagen.id3._frames',
        'mutagen._vorbis', 'mutagen._tags',
        'PIL', 'PIL.Image', 'PIL.ImageTk', 'PIL.ImageGrab',
        'PIL.ImageDraw', 'PIL.ImageFilter', 'PIL._imaging',
        'tkinterdnd2',
        'requests', 'urllib3', 'charset_normalizer', 'certifi', 'idna',
    ],
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='RoonTag',
    debug=False,
    strip=False,
    upx=False,
    console=False,
    argv_emulation=True,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    name='RoonTag',
)

app = BUNDLE(
    coll,
    name='RoonTag.app',
    icon=$ICNS_ARG,
    bundle_identifier='com.mark.roontag',
    info_plist={
        'CFBundleName': 'RoonTag',
        'CFBundleDisplayName': 'RoonTag',
        'CFBundleVersion': '$VERSION',
        'CFBundleShortVersionString': '$VERSION',
        'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '12.0',
        'CFBundleDocumentTypes': [{
            'CFBundleTypeName': 'Audio File',
            'CFBundleTypeExtensions': ['mp3','flac','aif','aiff','wav','m4a'],
            'CFBundleTypeRole': 'Editor',
        }],
        'NSAppleEventsUsageDescription':
            'RoonTag needs to access files to tag music.',
    },
)
SPECEOF

# ── 5. Build ─────────────────────────────────────────────────────────────────
echo "==> Building (this takes ~1 minute)…"
cd "$SCRIPT_DIR"
"$VENV/bin/pyinstaller" --clean --noconfirm RoonTag.spec 2>&1 | grep -v "^INFO:"

# ── 6. Ad-hoc code sign (required on Apple Silicon) ─────────────────────────
echo "==> Signing…"
codesign --force --deep --sign - "$DIST/RoonTag.app" 2>/dev/null && echo "  Signed ok" || echo "  (signing skipped)"

# ── 7. Install to /Applications ─────────────────────────────────────────────
echo "==> Installing to /Applications…"
rm -rf /Applications/RoonTag.app
cp -r "$DIST/RoonTag.app" /Applications/RoonTag.app

# ── 8. Register with Launch Services ────────────────────────────────────────
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f /Applications/RoonTag.app 2>/dev/null || true

echo ""
echo "✓  RoonTag v$VERSION installed at /Applications/RoonTag.app"
echo ""
echo "Launch:   open /Applications/RoonTag.app"
echo "Log:      ~/Library/Logs/RoonTag.log"
echo ""
echo "If macOS shows a security warning, go to:"
echo "  System Settings → Privacy & Security → Open Anyway"
