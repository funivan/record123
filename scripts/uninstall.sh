#!/usr/bin/env bash
set -u

BUNDLE_ID="com.funivan.record123"
APP="/Applications/Record123.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
DELETE_RECORDINGS=0

for arg in "$@"; do
  case "$arg" in
    --with-recordings) DELETE_RECORDINGS=1 ;;
    -h|--help)
      echo "Usage: $0 [--with-recordings]"
      echo "Removes Record123 and its settings. Recordings are kept unless --with-recordings is used."
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

: "${HOME:?HOME must be set to uninstall Record123}"

killall Record123 2>/dev/null

tccutil reset All "$BUNDLE_ID"
tccutil reset All "com.record123.app" 2>/dev/null

osascript -e 'tell application "System Events" to delete (every login item whose name is "Record123")' 2>/dev/null

"$LSREGISTER" -u "$APP" 2>/dev/null
rm -rf "$APP"

rm -rf "$HOME/Library/Application Support/Record123"
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -rf "$HOME/Library/Caches/$BUNDLE_ID"
rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
rm -rf "$HOME/Library/HTTPStorages/$BUNDLE_ID"
rm -rf "$HOME/Library/WebKit/$BUNDLE_ID"
killall cfprefsd 2>/dev/null

if [[ "$DELETE_RECORDINGS" -eq 1 ]]; then
  rm -rf "$HOME/Movies/Record123"
else
  echo "Kept recordings in ~/Movies/Record123 (use --with-recordings to delete)"
fi

echo "Remaining Record123 files:"
find "$HOME/Library" /Library -iname "*record123*" 2>/dev/null

echo "Empty the Trash in Finder, then restart the Mac."
