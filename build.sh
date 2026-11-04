#!/bin/zsh
# Builds build/Ledge.app: the Swift app plus mediaremote-adapter (BSD-3-Clause) bundled inside.
#   ./build.sh          the app
#   ./build.sh dmg      also packs site/Ledge.dmg
#   ./build.sh release  a DMG that's signed, notarized by Apple and stapled, published as a GitHub Release
set -euo pipefail
cd "${0:A:h}"

if [[ ${1:-} == release && -n $(git status --porcelain) ]]; then
  echo "Commit source changes before releasing so the archive matches its Git tag."
  exit 1
fi

# Sign with your Developer ID when this Mac has one: it's what notarization needs, and a stable identity
# keeps Accessibility and the other permissions across rebuilds. Without one, builds are signed ad hoc.
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
if [[ ${1:-} == release && -z $IDENTITY ]]; then
  echo "No Developer ID Application certificate in your keychain."
  echo "Create one in Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application."
  exit 1
fi
if [[ -n $IDENTITY ]]; then
  SIGN=(codesign --force --timestamp --options runtime --sign "$IDENTITY")
else
  SIGN=(codesign --force --sign -)
fi

ADAPTER_TAG=v0.7.7
A=vendor/mediaremote-adapter
if [[ ! -d $A/build/MediaRemoteAdapter.framework ]]; then
  [[ -d $A ]] || git clone -q --branch $ADAPTER_TAG --depth 1 https://github.com/ungive/mediaremote-adapter.git $A
  # Force Xcode's clang: a cmake from another toolchain (e.g. Android NDK) otherwise picks its own compiler.
  CC=$(xcrun -f clang) CXX=$(xcrun -f clang++) OBJC=$(xcrun -f clang) OBJCXX=$(xcrun -f clang++) \
    cmake -S $A -B $A/build >/dev/null
  cmake --build $A/build
fi

swift build -c release
SPARKLE=.build/artifacts/sparkle/Sparkle
SPARKLE_FRAMEWORK=$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
[[ -d $SPARKLE_FRAMEWORK ]] || { echo "Sparkle's pinned framework is missing; run swift package resolve."; exit 1; }
APP=build/Ledge.app
rm -rf $APP
mkdir -p $APP/Contents/{MacOS,Resources,Frameworks}
cp "$(swift build -c release --show-bin-path)/Ledge" $APP/Contents/MacOS/
cp Info.plist $APP/Contents/
cp Branding/AppIcon.icns $APP/Contents/Resources/ # regenerate with: swift Branding/make-icon.swift
cp -R Icons $APP/Contents/Resources/ # Solar icons, CC BY 4.0 (credit in Icons/LICENSE.txt)
cp $A/bin/mediaremote-adapter.pl $APP/Contents/Resources/
cp $A/LICENSE $APP/Contents/Resources/mediaremote-adapter-LICENSE.txt
cp -R $A/build/MediaRemoteAdapter.framework $APP/Contents/Frameworks/
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
# Sign Sparkle's nested helpers first, retaining their sandbox entitlements and symlinks.
S=$APP/Contents/Frameworks/Sparkle.framework/Versions/B
"${SIGN[@]}" --preserve-metadata=entitlements "$S/XPCServices/Downloader.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$S/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$S/Updater.app"
"${SIGN[@]}" --preserve-metadata=entitlements "$S/Autoupdate"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" $APP/Contents/Frameworks/MediaRemoteAdapter.framework
"${SIGN[@]}" --entitlements Ledge.entitlements $APP
codesign --verify --deep --strict "$APP"
echo "Built $APP (signed ${IDENTITY:-ad hoc}). Run: open $APP"

if [[ ${1:-} == (dmg|release) ]]; then
  STAGE=build/dmg
  rm -rf $STAGE site/Ledge.dmg
  mkdir -p $STAGE
  cp -R $APP $STAGE/
  ln -s /Applications $STAGE/Applications
  hdiutil create -quiet -volname Ledge -srcfolder $STAGE -fs HFS+ -format UDZO site/Ledge.dmg
  echo "Packed site/Ledge.dmg"
fi

# Apple checks the DMG and everything in it, then the ticket is stapled on so it opens even offline.
# One-time setup, which asks for your Apple ID, team ID and an app-specific password:
#   xcrun notarytool store-credentials ledge
if [[ ${1:-} == release ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
  # An archive referenced by a signed update feed must never change beneath the same version.
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    echo "Release v$VERSION already exists. Bump both version fields in Info.plist before releasing."
    exit 1
  fi
  EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Info.plist)
  ACTUAL_KEY=$("$SPARKLE/bin/generate_keys" --account com.ledge.Ledge -p)
  [[ $ACTUAL_KEY == $EXPECTED_KEY ]] || { echo "The Sparkle signing key does not match Info.plist."; exit 1; }
  codesign --force --timestamp --sign "$IDENTITY" site/Ledge.dmg
  echo "Sending to Apple for notarization (usually a few minutes)…"
  RESULT=$(xcrun notarytool submit site/Ledge.dmg --keychain-profile ledge --wait 2>&1) || true
  print -r -- "$RESULT"
  if [[ $RESULT != *"status: Accepted"* ]]; then
    echo "Notarization didn't pass. See why with: xcrun notarytool log <submission id> --keychain-profile ledge"
    exit 1
  fi
  xcrun stapler staple -q site/Ledge.dmg
  spctl --assess --type open --context context:primary-signature -v site/Ledge.dmg
  echo "site/Ledge.dmg is notarized."

  # Build the feed before publishing, then deploy it only after its archive is available.
  UPDATE_STAGE=build/updates/$VERSION
  rm -rf "$UPDATE_STAGE"
  mkdir -p "$UPDATE_STAGE"
  cp site/Ledge.dmg "$UPDATE_STAGE/Ledge.dmg"
  if [[ -f releases/mac-$VERSION.md ]]; then cp "releases/mac-$VERSION.md" "$UPDATE_STAGE/Ledge.md"; fi
  "$SPARKLE/bin/generate_appcast" --account com.ledge.Ledge --maximum-versions 1 --maximum-deltas 0 \
    --download-url-prefix "https://github.com/notsocj/ledge/releases/download/v$VERSION/" \
    --link https://keepledge.vercel.app --embed-release-notes -o "$UPDATE_STAGE/appcast.xml" "$UPDATE_STAGE"
  "$SPARKLE/bin/sign_update" --account com.ledge.Ledge --verify "$UPDATE_STAGE/appcast.xml"
  ARCHIVE_SIGNATURE=$(python3 scripts/verify-appcast.py "$UPDATE_STAGE/appcast.xml" site/Ledge.dmg Info.plist)
  "$SPARKLE/bin/sign_update" --account com.ledge.Ledge --verify site/Ledge.dmg "$ARCHIVE_SIGNATURE"
  NOTES=(--generate-notes)
  if [[ -f releases/mac-$VERSION.md ]]; then NOTES=(--notes-file "releases/mac-$VERSION.md"); fi
  gh release create "v$VERSION" site/Ledge.dmg --target "$(git rev-parse HEAD)" \
    --title "Ledge for Mac $VERSION" --latest "${NOTES[@]}"
  cp "$UPDATE_STAGE/appcast.xml" site/appcast.xml
  echo "Published v$VERSION: https://github.com/notsocj/ledge/releases/tag/v$VERSION"
  echo "Commit and deploy site/appcast.xml so installed copies can find this signed update."
fi
