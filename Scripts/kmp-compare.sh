#!/bin/zsh
# Kotlin Multiplatform experiment (docs/kmp-experiment.md): runs the Kotlin tests on the JVM and the iOS simulator,
# builds Shared.xcframework, then runs the Swift tests that compare the Kotlin port with VoiceoverKit.
# Needs JDK 17+; the Gradle wrapper downloads everything else. Not part of Scripts/check.sh.
set -e
cd "$(dirname "$0")/.."
destination=${CHECK_DESTINATION:-'platform=iOS Simulator,name=iPhone 17'}
./gradlew :shared:allTests :shared:assembleSharedReleaseXCFramework --console=plain -q
log=$(mktemp)
cd Packages/KMPComparison
if ! xcodebuild test -scheme KMPComparison-Package -destination "$destination" \
  -derivedDataPath .build/xcode >"$log" 2>&1; then
  grep -E 'error:|failed|recorded an issue' "$log" | head -40; echo "KMP COMPARISON FAILED"; exit 1
fi
grep -E 'Test run with' "$log"
echo "KMP COMPARISON OK"
