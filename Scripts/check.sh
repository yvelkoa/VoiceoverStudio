#!/bin/zsh
# Lint, translations, unit tests and a simulator build. Exits non-zero on the first failure.
set -e
cd "$(dirname "$0")/.."
xcodegen generate -q
swiftlint lint --strict --quiet
python3 Scripts/fill_strings.py --check
swift test --package-path Packages/VoiceoverKit 2>&1 | grep -E "Test run with" || { echo "TESTS FAILED"; exit 1; }
out=$(xcodebuild build -project VoiceoverStudio.xcodeproj -scheme VoiceoverStudio \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -quiet 2>&1 \
  | grep -E 'error:|warning:|BUILD FAILED' || true)
if [ -n "$out" ]; then echo "$out"; echo "BUILD FAILED"; exit 1; fi
echo "CHECK OK"
