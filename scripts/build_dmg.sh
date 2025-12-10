#!/usr/bin/env bash
set -euo pipefail

# Build a signed/notarized DMG for InplaceAI.
# Environment variables:
#   BUILD_ARCHS:  Space-delimited SwiftPM arch flags (default: "--arch arm64")
#   CODESIGN_ID:  Developer ID Application cert name or "-" for ad-hoc (required for distribution)
#   NOTARY_PROFILE: Keychain profile for `notarytool` (optional; skips notarization if empty)
#   DIST_DIR:     Output directory (default: dist)
#   DMG_NAME:     DMG filename (default: InplaceAI.dmg)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="InplaceAI"
DIST_DIR="${DIST_DIR:-dist}"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
BUILD_ARCHS="${BUILD_ARCHS:---arch arm64}"
APP_VERSION="${APP_VERSION:-1.0}"
ICON_SRC="${ICON_SRC:-${ROOT}/Assets/InplaceAIIcon.svg}"
ICON_DST="${ICON_DST:-${ROOT}/Sources/InplaceAI/Resources/AppIcon.icns}"

export SWIFTPM_CACHE_PATH="${SWIFTPM_CACHE_PATH:-${ROOT}/.build/cache}"
export SWIFTPM_CONFIGURATION_PATH="${SWIFTPM_CONFIGURATION_PATH:-${ROOT}/.build/config}"

cd "$ROOT"

ensure_icns() {
    if [[ -f "$ICON_DST" ]]; then
        return
    fi
    if [[ ! -f "$ICON_SRC" ]]; then
        echo "Warning: icon source not found at ${ICON_SRC}; skipping .icns generation." >&2
        return
    fi
    echo "Generating .icns from ${ICON_SRC}..."
    tmpdir="$(mktemp -d /tmp/inplaceai-icon.XXXXXX)"
    iconset="${tmpdir}/AppIcon.iconset"
    mkdir -p "$iconset"
    mkdir -p "$(dirname "$ICON_DST")"

    for size in 16 32 64 128 256 512 1024; do
        if ! sips -s format png -z "$size" "$size" "$ICON_SRC" --out "${iconset}/icon_${size}x${size}.png" >/dev/null; then
            echo "Warning: sips could not render SVG; skipping .icns generation." >&2
            rm -rf "$tmpdir"
            return
        fi
        if [[ "$size" -lt 1024 ]]; then
            retina=$((size * 2))
            if ! sips -s format png -z "$retina" "$retina" "$ICON_SRC" --out "${iconset}/icon_${size}x${size}@2x.png" >/dev/null; then
                echo "Warning: sips could not render SVG; skipping .icns generation." >&2
                rm -rf "$tmpdir"
                return
            fi
        fi
    done

    iconutil -c icns "$iconset" -o "$ICON_DST"
    rm -rf "$tmpdir"
}

ensure_icns

echo "Building release (${BUILD_ARCHS})..."
swift build -c release ${BUILD_ARCHS}

mkdir -p "$DIST_DIR"

APP_PATH=""
BUILT_APP="${ROOT}/.build/apple/Products/Release/${APP_NAME}.app"
ALT_APP="${ROOT}/.build/Release/${APP_NAME}.app"

if [[ -d "$BUILT_APP" ]]; then
    APP_PATH="$BUILT_APP"
elif [[ -d "$ALT_APP" ]]; then
    APP_PATH="$ALT_APP"
fi

STAGED_APP="${DIST_DIR}/${APP_NAME}.app"
rm -rf "$STAGED_APP"

if [[ -n "$APP_PATH" ]]; then
    echo "Staging app bundle..."
    rsync -a "$APP_PATH" "$DIST_DIR/"
else
    BIN_PATH="$(find "$ROOT/.build" -path "*/release/${APP_NAME}" -type f | head -n 1)"
    if [[ -z "$BIN_PATH" ]]; then
        echo "Error: built binary not found after build." >&2
        exit 1
    fi
    echo "Bundling app from binary at ${BIN_PATH}..."
    mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
    cp "$BIN_PATH" "$STAGED_APP/Contents/MacOS/${APP_NAME}"
    chmod +x "$STAGED_APP/Contents/MacOS/${APP_NAME}"

    RES_BUNDLE="$(find "$(dirname "$BIN_PATH")" -maxdepth 1 -type d -name "${APP_NAME}_${APP_NAME}.bundle" | head -n 1)"
    if [[ -n "$RES_BUNDLE" ]]; then
        rsync -a "$RES_BUNDLE" "$STAGED_APP/Contents/Resources/"
    fi

    cat > "$STAGED_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.inplaceai.desktop</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF
fi

if [[ -f "$ICON_DST" ]]; then
    cp "$ICON_DST" "$STAGED_APP/Contents/Resources/" || true
    if [[ -f "$STAGED_APP/Contents/Info.plist" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$STAGED_APP/Contents/Info.plist" >/dev/null 2>&1 || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$STAGED_APP/Contents/Info.plist" >/dev/null 2>&1 || true
    fi
fi

if [[ ! -d "$STAGED_APP" ]]; then
    echo "Error: app bundle not staged." >&2
    exit 1
fi

if [[ -n "${CODESIGN_ID:-}" ]]; then
    echo "Codesigning with '${CODESIGN_ID}'..."
    codesign --deep --force --options runtime --timestamp --sign "$CODESIGN_ID" "$STAGED_APP"
else
    echo "Skipping codesign (set CODESIGN_ID to sign for distribution)."
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "Submitting to notarization (profile: ${NOTARY_PROFILE})..."
    xcrun notarytool submit "$STAGED_APP" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$STAGED_APP"
else
    echo "Skipping notarization (set NOTARY_PROFILE to enable)."
fi

DMG_PATH="${DIST_DIR}/${DMG_NAME}"
rm -f "$DMG_PATH"
echo "Creating DMG at ${DMG_PATH}..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGED_APP" -ov -format UDZO "$DMG_PATH"

echo "DMG ready: ${DMG_PATH}"
