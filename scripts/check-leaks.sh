#!/bin/bash
# Fails if anything that identifies the machine or person who built Conveta is about to be
# published: home folder paths, the computer's name, local network domains, or e-mail addresses.
#
#   scripts/check-leaks.sh                 the files git tracks (CI runs this on every push)
#   scripts/check-leaks.sh Conveta.app     also every file inside a built app or disk image
set -uo pipefail
cd "$(dirname "$0")/.."

patterns=(
  '/Users/[A-Za-z0-9._-]+/'         # someone's home folder
  '/Volumes/[A-Za-z0-9 ._-]+/'      # an external disk's name
  '\.attlocal\.net|\.local\b|\.lan\b|\.home\.arpa'   # local network names
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'   # e-mail addresses
)
# Placeholders and public addresses that are fine to publish.
allowed='/Users/(Shared|runner|a)/|noreply@anthropic\.com|users\.noreply\.github\.com|@example\.(com|org)|git@github\.com|xmlns|@(2x|3x)|"@[a-z]'
# This Mac's own names, matched literally.
mine=()
for value in "$HOME" "$(scutil --get ComputerName 2>/dev/null)" "$(scutil --get LocalHostName 2>/dev/null)"; do
  [ -n "$value" ] && [ "$value" != "/Users/runner" ] && mine+=("$value")
done

found=0
report() { echo "LEAK  $1: $2"; found=1; }

while IFS= read -r file; do
  [ -f "$file" ] || continue
  case "$file" in *.png|*.jpg|*.car|*.icns) continue;; esac
  # This script holds the patterns themselves.
  [ "$file" = "scripts/check-leaks.sh" ] && continue
  hits=$(grep -nIE "$(IFS='|'; echo "${patterns[*]}")" "$file" 2>/dev/null | grep -vE "$allowed" | head -3)
  [ -n "$hits" ] && report "$file" "$hits"
  for value in "${mine[@]}"; do
    grep -qIF "$value" "$file" 2>/dev/null && report "$file" "contains this Mac's \"$value\""
  done
done < <(git ls-files)

for bundle in "$@"; do
  while IFS= read -r file; do
    for value in "${mine[@]}"; do
      # Count rather than `grep -q`, whose early exit would break the pipe and hide the match.
      count=$(strings -a "$file" 2>/dev/null | grep -cF "$value" || true)
      [ "${count:-0}" -gt 0 ] && report "$file" "contains this Mac's \"$value\""
    done
  done < <(find "$bundle" -type f)
done

if [ $found = 1 ]; then
  echo "Personal information found; fix it before publishing." >&2
  exit 1
fi
echo "No personal information found."
