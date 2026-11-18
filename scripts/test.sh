#!/bin/zsh
# Runs every check: ConvetaKit's tests, then the app's self-test inside the sandboxed build.
set -euo pipefail
cd "${0:A:h}/.."
echo "== ConvetaKit tests"
(cd Packages/ConvetaKit && swift test --scratch-path ~/Library/Developer/Conveta/kit 2>&1 | grep -E "✘|error:|Test run")
echo "== App build"
scripts/build.sh
echo "== App self-test"
osascript -e 'tell application id "com.1804audio.Conveta" to quit' 2>/dev/null || true
sleep 0.5
~/Applications/Conveta.app/Contents/MacOS/Conveta --selftest
