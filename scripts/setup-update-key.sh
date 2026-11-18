#!/bin/bash
# Makes the EdDSA key Sparkle signs updates with (once per project, stored in the login keychain
# under the account "conveta"), checks its public half matches SUPublicEDKey in Info.plist, and
# gives the private half to the repository as SPARKLE_PRIVATE_KEY. The key never touches the repo;
# a temporary copy exists only for the upload and is deleted at once.
#
#   scripts/setup-update-key.sh
#
# Keep the key: without it, installed copies can't verify new updates. Back it up with
#   generate_keys --account conveta -x <file>   and store the file somewhere safe and offline.
set -euo pipefail
cd "$(dirname "$0")/.."
repository=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
version=2.10.1
tools=${SPARKLE_BIN:-$HOME/Library/Developer/Conveta/sparkle/bin}

if [ ! -x "$tools/generate_keys" ]; then
  mkdir -p "$(dirname "$tools")"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" |
    tar -xJ -C "$(dirname "$tools")"
fi

public=$("$tools/generate_keys" --account conveta -p 2>/dev/null || true)
if [ -z "$public" ]; then
  "$tools/generate_keys" --account conveta >/dev/null
  public=$("$tools/generate_keys" --account conveta -p)
fi
expected=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" App/Resources/Info.plist)
if [ "$public" != "$expected" ]; then
  echo "The key in this keychain doesn't match SUPublicEDKey in App/Resources/Info.plist." >&2
  echo "Use the Mac that holds the original key, or (for a brand-new project) put this public key" >&2
  echo "in Info.plist: $public" >&2
  exit 1
fi

key=$(mktemp -u)
trap 'rm -f "$key"' EXIT
"$tools/generate_keys" --account conveta -x "$key" >/dev/null
gh secret set SPARKLE_PRIVATE_KEY --repo "$repository" < "$key"
echo "SPARKLE_PRIVATE_KEY set for $repository."
