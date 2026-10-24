#!/bin/zsh
# Usage:
#   ./build.sh            local build (host arch, local signing identity)
#   ./build.sh --full     local build, quit running app, relaunch
#   ./build.sh --release  universal build, Developer ID + hardened runtime, notarize, zip
#   ./build.sh -h|--help  show this help
#   ./build.sh --use-default       also wipe saved settings (devices, theme, style, area) so the app starts with defaults
#   ./build.sh --reset-permission  also reset Screen Recording, Camera and Microphone permissions
#   The two flags combine with each other and with --full; either one quits and relaunches the app.
#
# Release env:
#   SIGN_ID         Developer ID Application identity (default: first one found in keychain), "-" for ad-hoc
#   NOTARY_PROFILE  notarytool keychain profile (xcrun notarytool store-credentials <name>)
#   VERSION / BUILD CFBundleShortVersionString / CFBundleVersion
set -e
cd "$(dirname "$0")"
FULL=0
RELEASE=0
USE_DEFAULT=0
RESET_PERMISSION=0
for arg in "$@"; do
    case $arg in
        -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        --full) FULL=1 ;;
        --release) RELEASE=1 ;;
        --use-default) USE_DEFAULT=1; FULL=1 ;;
        --reset-permission) RESET_PERMISSION=1; FULL=1 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done
BUNDLE_ID=com.funivan.record123
VERSION=${VERSION:-1.0}
BUILD=${BUILD:-1}

if (( FULL )); then
    pkill -x Record123 || true
    while pgrep -x Record123 >/dev/null; do sleep 0.2; done
fi

if (( USE_DEFAULT )); then
    defaults delete $BUNDLE_ID 2>/dev/null || true
    echo "Saved settings reset"
fi
if (( RESET_PERMISSION )); then
    tccutil reset All $BUNDLE_ID
fi

if (( RELEASE )); then
    swift build -c release --arch arm64 --arch x86_64
    BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Record123
    [[ "$(lipo -archs $BIN)" == *x86_64*arm64* || "$(lipo -archs $BIN)" == *arm64*x86_64* ]] || { echo "Not a universal binary: $BIN"; exit 1; }
else
    swift build -c release
    BIN=.build/release/Record123
fi

APP=Record123.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN $APP/Contents/MacOS/Record123
cp Resources/AppIcon.icns $APP/Contents/Resources/AppIcon.icns
cp -R Resources/Wallpapers $APP/Contents/Resources/Wallpapers
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>Record123</string>
<key>CFBundleIdentifier</key><string>com.funivan.record123</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Record123</string>
<key>CFBundleDisplayName</key><string>Record123</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.video</string>
<key>NSHumanReadableCopyright</key><string>© $(date +%Y) Ivan Shcherbak (funivan)</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticTermination</key><false/>
<key>NSSupportsSuddenTermination</key><false/>
<key>NSCameraUsageDescription</key><string>Record123 records your camera as an overlay.</string>
<key>NSCameraUseContinuityCameraDeviceType</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Record123 records your voice.</string>
<key>NSScreenCaptureUsageDescription</key><string>Record123 records your screen.</string>
</dict></plist>
PLIST
plutil -lint $APP/Contents/Info.plist >/dev/null

SIGN_OPTS=(--force --options runtime --entitlements Record123.entitlements)
if (( RELEASE )); then
    SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')}
    [[ -z "$SIGN_ID" ]] && { echo "No Developer ID Application identity found; set SIGN_ID"; exit 1; }
    [[ "$SIGN_ID" != "-" ]] && SIGN_OPTS+=(--timestamp)
    codesign "${SIGN_OPTS[@]}" -s "$SIGN_ID" $APP
    codesign --verify --strict --verbose=2 $APP
    ZIP=Record123-$VERSION.zip
    rm -f $ZIP
    ditto -c -k --keepParent $APP $ZIP
    if [[ -n "$NOTARY_PROFILE" ]]; then
        xcrun notarytool submit $ZIP --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple $APP
        rm -f $ZIP
        ditto -c -k --keepParent $APP $ZIP
        spctl -a -vv -t exec $APP
    else
        echo "NOTARY_PROFILE not set: $ZIP is signed but not notarized"
    fi
    echo "Built $ZIP"
else
    ID="Record123 Local Signing"
    if security find-identity -p codesigning | grep -q "$ID"; then
        codesign "${SIGN_OPTS[@]}" -s "$ID" $APP
    else
        codesign "${SIGN_OPTS[@]}" -s - $APP
    fi
    echo "Built $APP"
fi
if (( FULL )); then open $APP; fi
