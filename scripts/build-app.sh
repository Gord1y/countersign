#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

usage() {
  echo "usage: build-app.sh [--universal]" >&2
  exit 2
}

universal=0
while [ "$#" -gt 0 ]; do
  case $1 in
  --universal) universal=1 ;;
  *) usage ;;
  esac
  shift
done

if [ "$universal" -eq 1 ]; then
  swift build -c release --arch arm64 --arch x86_64 --product countersign
  binary=.build/apple/Products/Release/countersign
else
  swift build -c release --product countersign
  binary=.build/release/countersign
fi

app="$(pwd -P)/.build/Countersign.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/countersign"
cp scripts/app/Info.plist "$app/Contents/Info.plist"
cp scripts/app/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
version=$("$app/Contents/MacOS/countersign" --version | sed 's/^countersign //')
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"
printf '%s' 'APPL????' >"$app/Contents/PkgInfo"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "$app"
