#!/bin/zsh
# Builds a release: universal app, signed with Developer ID, notarized and stapled, packed into a
# signed DMG, plus a Sparkle appcast entry signed with the EdDSA update key.
#
#   scripts/release.sh 1.2.0
#   SKIP_NOTARIZE=1 scripts/release.sh 1.2.0     dry run: everything but Apple's notary service
#
# Needs (locally):  a "Developer ID Application" certificate in the keychain,
#                   `xcrun notarytool store-credentials conveta` done once,
#                   the Sparkle key in the keychain (generate_keys --account conveta).
# Needs (in CI):    NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID and SPARKLE_KEY_FILE, see release.yml.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=${1:?usage: scripts/release.sh <version>}
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD)}
OUT=build/release
DERIVED=${DERIVED:-$HOME/Library/Developer/Conveta/ReleaseData}
SPARKLE=${SPARKLE_BIN:-$HOME/Library/Developer/Conveta/sparkle/bin}
REPO=${GITHUB_REPOSITORY:-mannobeats/conveta}
rm -rf $OUT && mkdir -p $OUT

[[ -x Vendor/FFmpeg/bin/ffmpeg ]] || scripts/build-ffmpeg.sh
lipo -info Vendor/FFmpeg/bin/ffmpeg | grep -q "x86_64 arm64\|arm64 x86_64" || { echo "FFmpeg helper must be universal"; exit 1; }

echo "==> Building Conveta $VERSION ($BUILD_NUMBER)"
xcodegen generate --quiet
xcodebuild -project Conveta.xcodeproj -scheme Conveta -configuration Release -derivedDataPath $DERIVED \
  -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD_NUMBER \
  OTHER_CODE_SIGN_FLAGS="--timestamp" build > $OUT/build.log 2>&1 || { grep -E "error:" $OUT/build.log | head -20; exit 1; }
APP=$DERIVED/Build/Products/Release/Conveta.app
ditto $APP $OUT/Conveta.app
codesign --verify --deep --strict --verbose=2 $OUT/Conveta.app
lipo -info $OUT/Conveta.app/Contents/MacOS/Conveta

notarize() { # file
  if [[ -n ${SKIP_NOTARIZE:-} ]]; then echo "    (skipped: SKIP_NOTARIZE)"; return; fi
  if [[ -n ${NOTARY_KEY_PATH:-} ]]; then
    xcrun notarytool submit "$1" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  else
    xcrun notarytool submit "$1" --keychain-profile conveta --wait
  fi
}

echo "==> Notarizing the app"
ditto -c -k --keepParent $OUT/Conveta.app $OUT/Conveta.zip
notarize $OUT/Conveta.zip
[[ -n ${SKIP_NOTARIZE:-} ]] || xcrun stapler staple $OUT/Conveta.app
rm $OUT/Conveta.zip

echo "==> Making the disk image"
STAGE=$OUT/dmg && mkdir -p $STAGE && ditto $OUT/Conveta.app $STAGE/Conveta.app && ln -s /Applications $STAGE/Applications
DMG=$OUT/Conveta-$VERSION.dmg
hdiutil create -volname "Conveta" -srcfolder $STAGE -fs APFS -format ULFO -ov $DMG >/dev/null
codesign --force --timestamp --sign "Developer ID Application" $DMG
notarize $DMG
if [[ -z ${SKIP_NOTARIZE:-} ]]; then
  xcrun stapler staple $DMG
  spctl --assess --type open --context context:primary-signature --verbose $DMG
fi

echo "==> Signing the update"
if [[ -n ${SPARKLE_KEY_FILE:-} ]]; then
  SIGNATURE=$($SPARKLE/sign_update --ed-key-file "$SPARKLE_KEY_FILE" $DMG)
else
  SIGNATURE=$($SPARKLE/sign_update --account conveta $DMG)
fi
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" $OUT/Conveta.app/Contents/Info.plist)
cat > $OUT/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Conveta</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Conveta $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Conveta-$VERSION.dmg" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML
echo "Done: $DMG and $OUT/appcast.xml"
