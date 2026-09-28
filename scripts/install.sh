#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product countersign
dest="$HOME/.local/bin/countersign"
mkdir -p "$(dirname "$dest")"
cp .build/release/countersign "$dest.new"
chmod 755 "$dest.new"
mv -f "$dest.new" "$dest"
echo "installed $dest"
