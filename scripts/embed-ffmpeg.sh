#!/bin/zsh
# Xcode build phase: copies the FFmpeg helpers into Conveta.app/Contents/Helpers and signs them
# with the hardened runtime, as notarization requires.
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
  # Release builds need a secure timestamp for notarization; debug builds skip the network round trip.
  TIMESTAMP=$([[ "$CONFIGURATION" == "Release" ]] && echo "--timestamp" || echo "--timestamp=none")
  codesign --force --options runtime $TIMESTAMP \
    --entitlements "$SRCROOT/App/Resources/Helper.entitlements" \
    --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST/$tool"
done
