#!/bin/zsh
# Lint, translations, package tests, app tests on the simulator. Exits non-zero on the first failure.
# The destination defaults to an iPhone 17 simulator; override with CHECK_DESTINATION.
set -e
cd "$(dirname "$0")/.."
destination=${CHECK_DESTINATION:-'platform=iOS Simulator,name=iPhone 17'}
xcodegen generate -q
swiftlint lint --strict --quiet
python3 Scripts/fill_strings.py --check
# The summary line is printed for a failed run too, so the exit status decides, not the grep.
package_log=$(mktemp)
if ! swift test --package-path Packages/VoiceoverKit >"$package_log" 2>&1; then
  grep -E 'error:|recorded an issue|Test run with' "$package_log" | head -40; echo "PACKAGE TESTS FAILED"; exit 1
fi
grep -E "Test run with" "$package_log"
log=$(mktemp)
if ! xcodebuild test -project VoiceoverStudio.xcodeproj -scheme VoiceoverStudio \
  -destination "$destination" CODE_SIGNING_ALLOWED=NO -quiet >"$log" 2>&1; then
  grep -E 'error:|failed|recorded an issue' "$log" | head -40; echo "APP TESTS FAILED"; exit 1
fi
out=$(grep -E 'error:|warning:' "$log" | grep -v 'appintents' || true)
if [ -n "$out" ]; then echo "$out"; echo "BUILD WARNINGS"; exit 1; fi
echo "CHECK OK"
