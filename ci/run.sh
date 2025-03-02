#!/bin/bash

heading() {
  echo ""
  echo -e "\033[0;35m** ${*} **\033[0m"
  echo ""
}

fail() {
  >&2 echo "error: $@"
  exit 1
}

xcb() {
  LOG="$1"
  heading "$LOG"
  shift
  export NSUnbufferedIO=YES
  set -o pipefail && xcodebuild \
    -workspace SPTDataLoader.xcworkspace \
    -UseSanitizedBuildSystemEnvironment=YES \
    -derivedDataPath build/DerivedData \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    "$@" | xcpretty || fail "$LOG failed"
}

if [ -n "$TRAVIS_BUILD_ID" ]; then
  heading "Installing Tools"
  gem install xcpretty cocoapods
fi

heading "Linting Podspec"
pod spec lint SPTDataLoader.podspec --quick || \
  fail "Podspec lint failed"

heading "Validating License Conformance"
git ls-files | egrep "\\.(h|m|mm)$" | \
  xargs ci/validate_license_conformance.sh ci/expected_license_header.txt || \
  fail "License Validation Failed"

#
# BUILD LIBRARIES
#

build_library() {
  xcb "Build Library [$1]" \
    build -scheme SPTDataLoader \
    -sdk "$1" \
    -configuration Release
}

build_library iphoneos
build_library iphonesimulator
build_library macosx
build_library watchos
build_library watchsimulator
build_library appletvos
build_library appletvsimulator

#
# BUILD FRAMEWORKS
#

build_framework() {
  xcb "Build Framework [$1]" \
    build -scheme "$1" \
    -configuration Release
}

build_framework SPTDataLoader-iOS
build_framework SPTDataLoader-OSX
build_framework SPTDataLoader-TV
build_framework SPTDataLoader-Watch

#
# BUILD DEMO APP
#

xcb "Build Demo App for Simulator" \
  build -scheme "SPTDataLoaderDemo" \
  -sdk iphonesimulator \
  -configuration Release

#
# RUN TESTS
#

xcb "Run tests for macOS" test \
  -scheme "SPTDataLoader" \
  -enableCodeCoverage YES \
  -sdk macosx

LATEST_IOS_SDK="$(/usr/libexec/PlistBuddy -c "Print :Version" "$(xcrun --show-sdk-path --sdk iphonesimulator)/SDKSettings.plist")"
xcb "Run tests for iOS" test \
  -scheme "SPTDataLoader" \
  -enableCodeCoverage YES \
  -destination "platform=iOS Simulator,name=iPhone 8,OS=$LATEST_IOS_SDK"

LATEST_TVOS_SDK="$(/usr/libexec/PlistBuddy -c "Print :Version" "$(xcrun --show-sdk-path --sdk iphonesimulator)/SDKSettings.plist")"
xcb "Run tests for tvOS" test \
  -scheme "SPTDataLoader" \
  -enableCodeCoverage YES \
  -destination "platform=tvOS Simulator,name=Apple TV,OS=$LATEST_TVOS_SDK"

#
# CODECOV
#
curl -sfL https://codecov.io/bash > build/codecov.sh
chmod +x build/codecov.sh
[[ -z "$TRAVIS_BUILD_ID" ]] && CODECOV_EXTRA="-d"
build/codecov.sh -D build/DerivedData -X xcodellvm $CODECOV_EXTRA
