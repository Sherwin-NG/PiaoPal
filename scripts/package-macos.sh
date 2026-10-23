#!/bin/bash
# Build without a Developer ID certificate. Output is ad-hoc signed, not notarized.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
VERSION="${1:-$SOURCE_VERSION}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || "$VERSION" != "$SOURCE_VERSION" ]]; then
  echo "Version must match Info.plist ($SOURCE_VERSION); received: $VERSION" >&2
  exit 1
fi
SOURCE_BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
BUILD_NUMBER="${BUILD_NUMBER:-$SOURCE_BUILD_NUMBER}"
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo 'BUILD_NUMBER must be a non-negative integer.' >&2
  exit 1
fi

DIST_DIR="${DIST_DIR:-$REPO_DIR/dist}"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/build/release-macos}"
mkdir -p "$DIST_DIR" "$BUILD_DIR"
DIST_DIR="$(cd -- "$DIST_DIR" && pwd)"
BUILD_DIR="$(cd -- "$BUILD_DIR" && pwd)"
# Every invocation owns its staging tree; prior outputs are never used as inputs.
STAGING_DIR="$(mktemp -d "$BUILD_DIR/staging.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT

echo 'Building arm64 + x86_64 with the existing runtime Metal shader fallback.'
xcodebuild \
  -project PiaoPal.xcodeproj \
  -scheme PiaoPal \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  build \
  'ARCHS=arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_SOURCE_FILE_NAMES=Shader.metal

APP_PATH="$STAGING_DIR/PiaoPal.app"
ditto "$BUILD_DIR/DerivedData/Build/Products/Release/PiaoPal.app" "$APP_PATH"
mkdir -p "$APP_PATH/Contents/Resources"
cp LICENSE "$APP_PATH/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
cmp LICENSE "$APP_PATH/Contents/Resources/LICENSE"
cmp THIRD_PARTY_NOTICES.md "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
cmp Resources/Sprites/piaopiao.png "$APP_PATH/Contents/Resources/Sprites/piaopiao.png"
cmp Resources/Sprites/piaopiao-walk.png "$APP_PATH/Contents/Resources/Sprites/piaopiao-walk.png"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
python3 - "$APP_PATH/Contents/Info.plist" "$VERSION" <<'PY_CHECK'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
expected = {
    'CFBundleIdentifier': 'io.github.sherwinng.PiaoPal',
    'CFBundleName': 'PiaoPal',
    'CFBundleExecutable': 'PiaoPal',
    'CFBundleShortVersionString': sys.argv[2],
    'LSMinimumSystemVersion': '13.0',
}
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f'Incorrect packaged identity: {key}={info.get(key)!r}; expected {value!r}')
if any(key.startswith('PiaoPalPreview') for key in info):
    raise SystemExit('Release packages must not contain developer preview settings')
PY_CHECK

EXECUTABLE="$APP_PATH/Contents/MacOS/PiaoPal"
lipo "$EXECUTABLE" -verify_arch arm64 x86_64
codesign --force --sign - --timestamp=none --entitlements PiaoPal.entitlements "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

BASE_NAME="PiaoPal-v$VERSION-macOS-universal"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$STAGING_DIR/$BASE_NAME.zip"

DMG_CONTENTS="$STAGING_DIR/dmg"
mkdir -p "$DMG_CONTENTS"
ditto "$APP_PATH" "$DMG_CONTENTS/PiaoPal.app"
cp LICENSE "$DMG_CONTENTS/LICENSE"
cp THIRD_PARTY_NOTICES.md "$DMG_CONTENTS/THIRD_PARTY_NOTICES.md"
ln -s /Applications "$DMG_CONTENTS/Applications"
hdiutil create -volname "PiaoPal $VERSION" -srcfolder "$DMG_CONTENTS" \
  -ov -format UDZO "$STAGING_DIR/$BASE_NAME.dmg"
hdiutil verify "$STAGING_DIR/$BASE_NAME.dmg"

mv -f "$STAGING_DIR/$BASE_NAME.zip" "$DIST_DIR/$BASE_NAME.zip"
mv -f "$STAGING_DIR/$BASE_NAME.dmg" "$DIST_DIR/$BASE_NAME.dmg"
python3 scripts/release-checksums.py --version "$VERSION" --directory "$DIST_DIR"
(cd "$DIST_DIR" && shasum -a 256 --check SHA256SUMS.txt)
echo "Packages verified: $DIST_DIR/$BASE_NAME.{dmg,zip}"
