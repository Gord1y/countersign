#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

usage() {
  echo "usage: package-release.sh <version>" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
version=$1

scripts/build-app.sh --universal
binary=.build/apple/Products/Release/countersign
built_version=$("$binary" --version | sed 's/^countersign //')
if [ "$built_version" != "$version" ]; then
  echo "package-release: built version $built_version does not match requested version $version" >&2
  exit 1
fi

check_universal() {
  output=$(file "$1")
  echo "$output"
  case "$output" in
  *"2 architectures"*) ;;
  *)
    echo "package-release: $1 is not a universal binary: $output" >&2
    exit 1
    ;;
  esac
}

root="$(pwd -P)"
stage_root="$root/.build/release-stage"
stage="$stage_root/countersign-$version"
rm -rf "$stage_root"
mkdir -p "$stage"

cp "$binary" "$stage/countersign"
codesign --force --sign - "$stage/countersign"
cp -R "$root/.build/Countersign.app" "$stage/Countersign.app"
cp "$root/LICENSE" "$stage/LICENSE"
cp "$root/README.md" "$stage/README.md"

check_universal "$stage/countersign"
check_universal "$stage/Countersign.app/Contents/MacOS/countersign"
codesign --verify --strict "$stage/Countersign.app"

artifacts="$root/.build/release-artifacts"
rm -rf "$artifacts"
mkdir -p "$artifacts"

versioned_tarball="$artifacts/countersign-$version-macos.tar.gz"
COPYFILE_DISABLE=1 tar -czf "$versioned_tarball" -C "$stage_root" "countersign-$version"
(cd "$artifacts" && shasum -a 256 "$(basename "$versioned_tarball")" >"$(basename "$versioned_tarball").sha256")

unversioned_tarball="$artifacts/countersign-macos.tar.gz"
cp "$versioned_tarball" "$unversioned_tarball"
(cd "$artifacts" && shasum -a 256 "$(basename "$unversioned_tarball")" >"$(basename "$unversioned_tarball").sha256")

echo "package-release: $artifacts"
