#!/bin/bash
# Build and launch an isolated local sprite preview; does not install or replace PiaoPal.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ATLAS_PATH="$REPO_DIR/Resources/Sprites/piaopiao.png"
FOLLOW=0
BUILD_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --follow) FOLLOW=1 ;;
    --build-only) BUILD_ONLY=1 ;;
    --help|-h)
      echo 'Usage: scripts/preview-ai-pet.sh [--follow] [--build-only] [/absolute/atlas.png-or-gif]'
      echo 'Default: play all 17 animation states, 2.4 seconds each, at the screen center.'
      echo '--follow: use the existing cursor-following simulation instead.'
      exit 0 ;;
    /*) ATLAS_PATH="$arg" ;;
    *) echo "Unknown argument (atlas path must be absolute): $arg" >&2; exit 1 ;;
  esac
done

if [[ "$BUILD_ONLY" == 0 && ! -f "$ATLAS_PATH" ]]; then
  echo "Sprite atlas not found: $ATLAS_PATH" >&2
  exit 1
fi

cd "$REPO_DIR"
BUILD_DIR="$REPO_DIR/build/ai-pet-preview"
APP_PATH="$BUILD_DIR/PiaoPal Sprite Preview.app"
mkdir -p "$BUILD_DIR"
BUILD_LOG="$BUILD_DIR/build.log"

echo 'Building the native-architecture preview (runtime Metal shader fallback).'
if ! xcodebuild \
  -project PiaoPal.xcodeproj \
  -scheme PiaoPal \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  build \
  "ARCHS=$(uname -m)" \
  ONLY_ACTIVE_ARCH=YES \
  PRODUCT_BUNDLE_IDENTIFIER=io.github.sherwinng.PiaoPal.preview \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_SOURCE_FILE_NAMES=Shader.metal \
  "CLANG_MODULE_CACHE_PATH=$BUILD_DIR/ModuleCache" \
  > "$BUILD_LOG" 2>&1; then
  tail -n 80 "$BUILD_LOG" >&2
  echo "Build failed; full log: $BUILD_LOG" >&2
  exit 1
fi

ditto "$BUILD_DIR/DerivedData/Build/Products/Debug/PiaoPal.app" "$APP_PATH"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName PiaoPal Sprite Preview' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName PiaoPal Sprite Preview' "$APP_PATH/Contents/Info.plist"
codesign --force --sign - --timestamp=none --entitlements PiaoPal.entitlements "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

if [[ "$BUILD_ONLY" == 1 ]]; then
  echo "Preview built: $APP_PATH"
  exit 0
fi

# Restart only this dedicated preview so reruns can switch between tour and follow mode.
/usr/bin/osascript -e 'if application id "io.github.sherwinng.PiaoPal.preview" is running then tell application id "io.github.sherwinng.PiaoPal.preview" to quit' >/dev/null 2>&1 || true
ARGS=(--preview-skin "$ATLAS_PATH")
if [[ "$FOLLOW" == 0 ]]; then ARGS+=(--preview-animations); fi
open -n "$APP_PATH" --args "${ARGS[@]}"
echo "Preview launched: $APP_PATH"
echo "Atlas: $ATLAS_PATH"
echo 'Right-click the preview paw icon in the menu bar to quit.'
