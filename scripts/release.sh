#!/bin/zsh
# Builds a release: universal app, signed with Developer ID, notarized and stapled, packed into a
# signed DMG, plus a Sparkle appcast entry signed with the EdDSA update key.
#
#   scripts/release.sh 1.2.0
#   SKIP_NOTARIZE=1 scripts/release.sh 1.2.0     dry run: everything but Apple's notary service
#
# Needs a "Developer ID Application" certificate in the keychain, the Sparkle key in the keychain
# (scripts/setup-update-key.sh) or SPARKLE_KEY_FILE, and for notarization APPLE_ID, APPLE_PASSWORD
# (an app-specific password) and APPLE_TEAM_ID in the environment, the same secrets
# scripts/setup-release-secrets.sh gives the Release workflow.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=${1:?usage: scripts/release.sh <version>}
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD)}
OUT=build/release
DERIVED=${DERIVED:-$HOME/Library/Developer/Conveta/ReleaseData}
SPARKLE=${SPARKLE_BIN:-$HOME/Library/Developer/Conveta/sparkle/bin}
REPO=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
IDENTITY=${APPLE_SIGNING_IDENTITY:-Developer ID Application}
TEAM_OVERRIDE=()
[[ -n ${APPLE_TEAM_ID:-} ]] && TEAM_OVERRIDE=(DEVELOPMENT_TEAM=$APPLE_TEAM_ID)
rm -rf $OUT && mkdir -p $OUT

[[ -x Vendor/FFmpeg/bin/ffmpeg ]] || scripts/build-ffmpeg.sh
lipo -info Vendor/FFmpeg/bin/ffmpeg | grep -q "x86_64 arm64\|arm64 x86_64" || { echo "FFmpeg helper must be universal"; exit 1; }

echo "==> Building Conveta $VERSION ($BUILD_NUMBER)"
xcodegen generate --quiet
xcodebuild -project Conveta.xcodeproj -scheme Conveta -configuration Release -derivedDataPath $DERIVED \
  -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD_NUMBER "${TEAM_OVERRIDE[@]}" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" build > $OUT/build.log 2>&1 || { grep -E "error:" $OUT/build.log | head -20; exit 1; }
APP=$DERIVED/Build/Products/Release/Conveta.app
ditto $APP $OUT/Conveta.app
codesign --verify --deep --strict --verbose=2 $OUT/Conveta.app
lipo -info $OUT/Conveta.app/Contents/MacOS/Conveta
scripts/check-leaks.sh $OUT/Conveta.app

# Has Apple notarize a file and staples the ticket. Fails with Apple's reasons when it's refused.
notarize() { # file
  if [[ -n ${SKIP_NOTARIZE:-} ]]; then echo "    (skipped: SKIP_NOTARIZE)"; return; fi
  : "${APPLE_ID:?Set APPLE_ID, APPLE_PASSWORD and APPLE_TEAM_ID to notarize (or SKIP_NOTARIZE=1).}"
  : "${APPLE_PASSWORD:?Set APPLE_ID, APPLE_PASSWORD and APPLE_TEAM_ID to notarize.}"
  : "${APPLE_TEAM_ID:?Set APPLE_ID, APPLE_PASSWORD and APPLE_TEAM_ID to notarize.}"
  local report=$(mktemp)
  xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_PASSWORD" \
    --wait --timeout 30m | tee "$report"
  # notarytool ends well whatever Apple decided; the verdict is in what it printed.
  if ! grep -q "status: Accepted" "$report"; then
    local submission=$(sed -n 's/^ *id: //p' "$report" | head -1)
    echo "Apple didn't accept $(basename "$1"). Its reasons:" >&2
    xcrun notarytool log "$submission" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_PASSWORD" >&2 || true
    rm -f "$report"; exit 1
  fi
  rm -f "$report"
}

# The ticket is fetched from Apple; in CI that connection drops now and then.
staple() { # file
  [[ -n ${SKIP_NOTARIZE:-} ]] && return
  for attempt in 1 2 3 4 5; do
    xcrun stapler staple "$1" && return
    [[ $attempt == 5 ]] && exit 1
    sleep $((attempt * 10))
  done
}

echo "==> Notarizing the app"
ditto -c -k --keepParent $OUT/Conveta.app $OUT/Conveta.zip
notarize $OUT/Conveta.zip
staple $OUT/Conveta.app
rm $OUT/Conveta.zip

echo "==> Making the disk image"
STAGE=$OUT/dmg && mkdir -p $STAGE && ditto $OUT/Conveta.app $STAGE/Conveta.app && ln -s /Applications $STAGE/Applications
DMG=$OUT/Conveta-$VERSION.dmg
hdiutil create -volname "Conveta" -srcfolder $STAGE -fs APFS -format ULFO -ov $DMG >/dev/null
codesign --force --timestamp --sign "$IDENTITY" $DMG
notarize $DMG
staple $DMG
[[ -n ${SKIP_NOTARIZE:-} ]] || spctl --assess --type open --context context:primary-signature --verbose $DMG

echo "==> Signing the update"
if [[ -z ${SPARKLE_KEY_FILE:-} ]]; then
  # Export the key from the keychain for this one signature (generate_keys can read its own item
  # without a keychain prompt), then delete the copy.
  SPARKLE_KEY_FILE=$(mktemp -u)
  trap 'rm -f "$SPARKLE_KEY_FILE"' EXIT
  $SPARKLE/generate_keys --account conveta -x "$SPARKLE_KEY_FILE" >/dev/null
fi
SIGNATURE=$($SPARKLE/sign_update --ed-key-file "$SPARKLE_KEY_FILE" $DMG)
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
