#!/bin/zsh
# Re-extracts every localizable string from a fresh build into the catalogs, then fills in the translations
# from Scripts/translations.py. Run it after adding or changing user-facing text.
set -e
cd "$(dirname "$0")/.."
dd=$(mktemp -d)
trap 'rm -rf "$dd"' EXIT
xcodegen generate -q
xcodebuild build -project VoiceoverStudio.xcodeproj -scheme VoiceoverStudio \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$dd" CODE_SIGNING_ALLOWED=NO -quiet
inter="$dd/Build/Intermediates.noindex"
xcrun xcstringstool sync App/Resources/Localizable.xcstrings \
  --stringsdata $(find "$inter" -name '*.stringsdata' -path '*/VoiceoverStudio.build/*')
xcrun xcstringstool sync Packages/VoiceoverKit/Sources/VoiceoverKit/Resources/Localizable.xcstrings \
  --stringsdata $(find "$inter" -name '*.stringsdata' -path '*/VoiceoverKit.build/*')
python3 Scripts/fill_strings.py
