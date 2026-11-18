#!/bin/zsh
# Builds Conveta, installs it to ~/Applications and (with --open) relaunches it.
# Usage: scripts/build.sh [--release] [--open]
set -euo pipefail
cd "${0:A:h}/.."

CONFIG=Debug
OPEN=0
for arg in "$@"; do
  case $arg in
    --release) CONFIG=Release ;;
    --open) OPEN=1 ;;
  esac
done

DERIVED=~/Library/Developer/Conveta/DerivedData
INSTALL=~/Applications/Conveta.app

xcodegen generate --quiet
LOG=$DERIVED/build.log
mkdir -p $DERIVED
if ! xcodebuild -project Conveta.xcodeproj -scheme Conveta -configuration $CONFIG \
     -derivedDataPath $DERIVED -destination 'platform=macOS' build > $LOG 2>&1; then
  grep -E "error:" $LOG | sort -u | head -30
  echo "BUILD FAILED (full log: $LOG)"
  exit 1
fi
WARNINGS=$(grep -E "warning:" $LOG | grep -v "appintentsmetadataprocessor" | sort -u || true)
if [[ -n $WARNINGS ]]; then echo "$WARNINGS"; echo "Build has warnings"; exit 1; fi
echo "BUILD SUCCEEDED"
APP=$DERIVED/Build/Products/$CONFIG/Conveta.app

if (( OPEN )); then
  osascript -e 'tell application id "com.1804audio.Conveta" to quit' 2>/dev/null || true
  sleep 0.5
fi
mkdir -p ~/Applications
rm -rf $INSTALL
ditto $APP $INSTALL
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSREGISTER -f -R -trusted $INSTALL
pluginkit -a $INSTALL/Contents/PlugIns/ConvetaFinder.appex 2>/dev/null || true
echo "Installed $INSTALL"
if (( OPEN )); then open $INSTALL; fi
