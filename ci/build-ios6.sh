#!/bin/bash
# Build OldSend for iOS 6+ (armv7) on Linux with Theos' iOS toolchain and the iOS 9.3 SDK.
# The upstream Makefile needs a Mac, Xcode and the iOS 3.1.3/4.2 SDKs (for armv6); this script
# builds the same sources for armv7 only, which covers the iPhone 3GS and later.
#
# Needs: THEOS (with toolchain/linux/iphone and sdks/iPhoneOS9.3.sdk), ldid, dpkg-deb.
# Output: build-ios6/OldSend.app and packages/com.lihaoyun6.oldsend_<version>_iphoneos-arm.deb
set -euo pipefail
cd "$(dirname "$0")/.."

TC="$THEOS/toolchain/linux/iphone/bin"
SDK="$THEOS/sdks/iPhoneOS9.3.sdk"
CC="$TC/clang"
MIN=6.0
OUT=build-ios6
APP="$OUT/OldSend.app"
OBJ="$OUT/obj"
rm -rf "$OUT" packages
mkdir -p "$OBJ" "$APP/en.lproj" "$APP/zh_CN.lproj" packages

CFLAGS=(-target "armv7-apple-ios$MIN" -isysroot "$SDK" -O2 -marm -mno-thumb
        -fno-objc-arc -fno-stack-protector -fno-modules
        -Iclient -Ivendor -Ivendor/mbedtls/include
        -Wno-deprecated-declarations -Wno-unused-command-line-argument)

objs=()
for src in client/*.m vendor/cJSON.c vendor/mbedtls/library/*.c; do
    obj="$OBJ/$(echo "$src" | tr '/' '_').o"
    "$CC" "${CFLAGS[@]}" -c "$src" -o "$obj"
    objs+=("$obj")
done

"$CC" "${CFLAGS[@]}" "${objs[@]}" \
    -framework UIKit -framework Foundation -framework QuartzCore \
    -framework CoreGraphics -framework SystemConfiguration \
    -o "$APP/OldSend"

# The media picker lives in its own library, as upstream: the app loads it at run time when the
# system has AssetsLibrary (iOS 4+), which keeps the main binary free of that dependency.
"$CC" -target "armv7-apple-ios$MIN" -isysroot "$SDK" -O2 -marm -mno-thumb -fno-objc-arc -fblocks -fno-modules -Iclient \
    -dynamiclib -install_name @executable_path/MediaPicker.dylib \
    -framework UIKit -framework Foundation -framework QuartzCore \
    -framework CoreGraphics -framework AssetsLibrary \
    media/MediaPickerViewController.m -o "$APP/MediaPicker.dylib"

ldid -S "$APP/OldSend"
ldid -S "$APP/MediaPicker.dylib"

# Resources: everything upstream's bundle step copies, plus any @2x (Retina) versions.
cp client/Info.plist "$APP/"
for f in client/Icon*.png client/Tab*.png client/ReceiveWifiLarge*.png client/Device*.png \
         client/SettingsBackground*.png client/RandomAlias*.png client/MediaVideoIcon*.png \
         client/Default*.png client/icons/*.png; do
    [ -f "$f" ] && cp "$f" "$APP/"
done
cp client/en.lproj/Localizable.strings "$APP/en.lproj/"
cp client/zh_CN.lproj/Localizable.strings "$APP/zh_CN.lproj/"
chmod 755 "$APP/OldSend" "$APP/MediaPicker.dylib"
find "$APP" -type f ! -name OldSend ! -name MediaPicker.dylib -exec chmod 644 {} +

# Package. dpkg-deb on Linux writes plain GNU tar, which iOS 6's dpkg 1.18 reads (upstream's
# macOS-made .deb carried pax headers with macOS metadata that it rejects).
VERSION=$(sed -n 's/^Version: //p' ci/control)
STAGE="$OUT/deb"
mkdir -p "$STAGE/DEBIAN" "$STAGE/Applications"
cp ci/control "$STAGE/DEBIAN/control"
cp -R "$APP" "$STAGE/Applications/"
dpkg-deb -Zgzip --root-owner-group -b "$STAGE" "packages/com.lihaoyun6.oldsend_${VERSION}_iphoneos-arm.deb"
ls -l packages/
