#!/bin/zsh
# Xcode build phase: copies the FFmpeg helpers into Conveta.app/Contents/Helpers and signs them
# with the sandbox-inherit entitlement, so they run inside the app's sandbox.
set -euo pipefail
SOURCE="$SRCROOT/Vendor/FFmpeg/bin"
DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
if [[ ! -x "$SOURCE/ffmpeg" || ! -x "$SOURCE/ffprobe" ]]; then
  echo "error: FFmpeg helper missing. Run scripts/build-ffmpeg.sh first."
  exit 1
fi
mkdir -p "$DEST"
for tool in ffmpeg ffprobe; do
  cp -f "$SOURCE/$tool" "$DEST/$tool"
  codesign --force --options runtime --timestamp=none \
    --entitlements "$SRCROOT/App/Resources/Helper.entitlements" \
    --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST/$tool"
done
