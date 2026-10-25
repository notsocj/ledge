#!/bin/zsh
# Builds build/Kestrel.app: the Swift app plus mediaremote-adapter (BSD-3-Clause) bundled inside.
set -euo pipefail
cd "${0:A:h}"

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
APP=build/Kestrel.app
rm -rf $APP
mkdir -p $APP/Contents/{MacOS,Resources,Frameworks}
cp "$(swift build -c release --show-bin-path)/Kestrel" $APP/Contents/MacOS/
cp Info.plist $APP/Contents/
cp -R Icons $APP/Contents/Resources/ # Solar icons, CC BY 4.0 (credit in Icons/LICENSE.txt)
cp $A/bin/mediaremote-adapter.pl $APP/Contents/Resources/
cp $A/LICENSE $APP/Contents/Resources/mediaremote-adapter-LICENSE.txt
cp -R $A/build/MediaRemoteAdapter.framework $APP/Contents/Frameworks/
codesign --force --sign - $APP/Contents/Frameworks/MediaRemoteAdapter.framework
codesign --force --sign - $APP
echo "Built $APP. Run: open $APP"
