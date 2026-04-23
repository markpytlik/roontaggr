#!/bin/bash
# Builds the RoonTag.app bundle with icon, renames from RoonTaggr if present.
# Run once:  bash make_roontag_app.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$SCRIPT_DIR/venv"
PY="$VENV/bin/python3"

OLD_APP="/Applications/RoonTaggr.app"
NEW_APP="/Applications/RoonTag.app"
ICNS_OUT="$SCRIPT_DIR/RoonTag.icns"

# ── 1. Generate icon ─────────────────────────────────────────────────────────
echo "==> Generating icon…"
"$PY" - <<'PYEOF'
import sys, math
from pathlib import Path
from PIL import Image, ImageDraw

ICONSET = Path("/tmp/RoonTag.iconset")
ICONSET.mkdir(exist_ok=True)

def make_icon(size):
    # ── background: blue-to-purple gradient ──────────────────────────────
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(0x00 * (1 - t) + 0x58 * t)
        g = int(0x7A * (1 - t) + 0x56 * t)
        b = int(0xFF * (1 - t) + 0xD6 * t)
        for x in range(size):
            img.putpixel((x, y), (r, g, b, 255))

    # ── rounded-rectangle mask (Apple icon shape) ─────────────────────────
    radius = int(size * 0.225)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255
    )
    img.putalpha(mask)
    draw = ImageDraw.Draw(img)

    # ── white tag shape ───────────────────────────────────────────────────
    pad   = size * 0.175
    tw    = size - 2 * pad          # tag width
    th    = tw * 1.08               # tag height
    cx    = size / 2
    ty    = (size - th) / 2 + size * 0.015  # top y

    hole_half = tw * 0.095          # half-width of hole notch

    # Polygon: clockwise from top-left corner
    tag_pts = [
        (cx - tw/2,           ty + tw * 0.13),   # TL after corner
        (cx - tw/2 + tw*0.13, ty),                # TL corner top
        (cx - hole_half - tw*0.05, ty),           # top, left of notch
        (cx - hole_half,      ty + size*0.028),   # notch left inner
        (cx + hole_half,      ty + size*0.028),   # notch right inner
        (cx + hole_half + tw*0.05, ty),           # top, right of notch
        (cx + tw/2 - tw*0.13, ty),                # TR corner top
        (cx + tw/2,           ty + tw * 0.13),   # TR after corner
        (cx + tw/2,           ty + th * 0.74),   # right side bottom
        (cx,                  ty + th),            # bottom point
        (cx - tw/2,           ty + th * 0.74),   # left side bottom
    ]
    draw.polygon(tag_pts, fill=(255, 255, 255, 242))

    # punch hole circle (gradient-coloured to look transparent)
    hr = tw * 0.082
    hcy = ty + size * 0.028
    t_h = hcy / size
    hfill = (
        int(0x00*(1-t_h) + 0x58*t_h),
        int(0x7A*(1-t_h) + 0x56*t_h),
        int(0xFF*(1-t_h) + 0xD6*t_h),
        255,
    )
    draw.ellipse([cx-hr, hcy-hr, cx+hr, hcy+hr], fill=hfill)

    # ── eighth note inside the tag ────────────────────────────────────────
    nc_x = cx + tw * 0.045
    nc_y = ty + th * 0.535
    note_color = (0x00, 0x40, 0xB8, 255)

    # note head (slightly tilted oval)
    nh_w = tw * 0.275
    nh_h = tw * 0.195
    draw.ellipse(
        [nc_x - nh_w/2, nc_y - nh_h/2,
         nc_x + nh_w/2, nc_y + nh_h/2],
        fill=note_color,
    )

    # stem
    sw     = max(2, int(size * 0.028))
    sx     = int(nc_x + nh_w/2 - sw * 0.6)
    sy_bot = int(nc_y - nh_h * 0.05)
    sy_top = int(sy_bot - tw * 0.56)
    draw.rectangle([sx, sy_top, sx + sw, sy_bot], fill=note_color)

    # flag (curved rightward from stem top)
    fw = tw * 0.20
    fh = tw * 0.26
    fp = [
        (sx + sw,        sy_top),
        (sx + sw + fw,   sy_top + fh * 0.28),
        (sx + sw + fw*0.85, sy_top + fh * 0.58),
        (sx + sw,        sy_top + fh * 0.72),
    ]
    draw.polygon(fp, fill=note_color)

    return img

# standard macOS iconset filenames
SPECS = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

rendered = {}
for fname, sz in SPECS:
    if sz not in rendered:
        rendered[sz] = make_icon(sz)
    rendered[sz].save(ICONSET / fname)

print(f"  Saved {len(SPECS)} PNGs to {ICONSET}")
PYEOF

# ── 2. Convert iconset → .icns ───────────────────────────────────────────────
echo "==> Running iconutil…"
iconutil -c icns /tmp/RoonTag.iconset -o "$ICNS_OUT"
echo "  Icon: $ICNS_OUT"

# ── 3. Build / update RoonTag.app ───────────────────────────────────────────
echo "==> Building RoonTag.app…"

# Remove old app if it exists under the old name
if [ -d "$OLD_APP" ] && [ "$OLD_APP" != "$NEW_APP" ]; then
    echo "  Removing old $OLD_APP…"
    rm -rf "$OLD_APP"
fi

MACOS="$NEW_APP/Contents/MacOS"
RES="$NEW_APP/Contents/Resources"
mkdir -p "$MACOS" "$RES"

# ── 4. Copy icon ─────────────────────────────────────────────────────────────
cp "$ICNS_OUT" "$RES/AppIcon.icns"

# ── 5. Write launcher ────────────────────────────────────────────────────────
cat > "$MACOS/RoonTag" << LAUNCHER
#!/bin/bash
# Set tkdnd library path if available (enables in-window drag-and-drop)
TKDND_PATH="\$(brew --prefix tkdnd 2>/dev/null)/lib"
if [ -d "\$TKDND_PATH" ]; then
    export TKDND_LIBRARY="\$TKDND_PATH"
fi
# Override destination folder if ROONTAGGR_DEST is set in the environment.
# On a remote machine pointing at a network share, set this in ~/.zshenv:
#   export ROONTAGGR_DEST="/Volumes/Mark-Studio/PARA/5. ROON"
LOG="\$HOME/Library/Logs/RoonTag.log"
exec "$VENV/bin/python3" "$SCRIPT_DIR/app.py" "\$@" >>"\$LOG" 2>&1
LAUNCHER
chmod +x "$MACOS/RoonTag"

# ── 6. Write Info.plist ──────────────────────────────────────────────────────
cat > "$NEW_APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>RoonTag</string>
    <key>CFBundleDisplayName</key>
    <string>RoonTag</string>
    <key>CFBundleIdentifier</key>
    <string>com.mark.roontag</string>
    <key>CFBundleVersion</key>
    <string>1.1</string>
    <key>CFBundleExecutable</key>
    <string>RoonTag</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Audio File</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>mp3</string>
                <string>flac</string>
                <string>aif</string>
                <string>aiff</string>
                <string>wav</string>
                <string>m4a</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
        </dict>
    </array>
    <key>NSAppleEventsUsageDescription</key>
    <string>RoonTag needs to access files to tag music.</string>
</dict>
</plist>
PLIST

# ── 7. Touch app so Finder picks up new icon ─────────────────────────────────
touch "$NEW_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$NEW_APP" 2>/dev/null || true

echo ""
echo "✓ RoonTag.app installed at $NEW_APP"
echo ""
echo "Launch with:  open /Applications/RoonTag.app"
echo "Or double-click it in Finder / Applications."
