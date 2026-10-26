#!/bin/zsh
# Builds build/Ledge.app: the Swift app plus mediaremote-adapter (BSD-3-Clause) bundled inside.
#   ./build.sh          the app
#   ./build.sh dmg      also packs site/Ledge.dmg, the file the site's Download buttons link to
#   ./build.sh release  a DMG that's signed, notarized by Apple and stapled, ready to publish
set -euo pipefail
cd "${0:A:h}"

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
"${SIGN[@]}" $APP/Contents/Frameworks/MediaRemoteAdapter.framework
"${SIGN[@]}" --entitlements Ledge.entitlements $APP
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
  echo "site/Ledge.dmg is notarized and ready to publish."
fi
