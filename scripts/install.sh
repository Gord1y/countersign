#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

usage() {
  echo "usage: install.sh [--app]" >&2
  exit 2
}

app=0
while [ "$#" -gt 0 ]; do
  case $1 in
  --app) app=1 ;;
  *) usage ;;
  esac
  shift
done

swift build -c release --product countersign
dest="$HOME/.local/bin/countersign"
mkdir -p "$(dirname "$dest")"
cp .build/release/countersign "$dest.new"
chmod 755 "$dest.new"
mv -f "$dest.new" "$dest"
echo "installed $dest"

if [ "$app" -eq 0 ]; then
  exit 0
fi

scripts/build-app.sh
apps_dir="$HOME/Applications"
app_dir="$apps_dir/Countersign.app"
app_existed_before=0
if [ -e "$app_dir" ]; then
  app_existed_before=1
fi
mkdir -p "$apps_dir"
rm -rf "$app_dir"
cp -R .build/Countersign.app "$app_dir"
echo "installed $app_dir"
if [ "$app_existed_before" -eq 1 ] && pgrep -f "$app_dir/Contents/MacOS/countersign" >/dev/null 2>&1; then
  echo "Countersign.app is still running the previous version; quit it from the menu bar and open it again"
fi
