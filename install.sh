#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "install: countersign only runs on macOS" >&2
  exit 1
fi

os_version=$(sw_vers -productVersion)
major=${os_version%%.*}
if [ "$major" -lt 14 ]; then
  echo "install: countersign needs macOS 14 or later, this Mac runs $os_version" >&2
  exit 1
fi

version=${COUNTERSIGN_VERSION:-}
if [ -n "$version" ]; then
  stripped_version=${version#v}
  if ! printf '%s' "$stripped_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "install: COUNTERSIGN_VERSION must be MAJOR.MINOR.PATCH, with an optional leading v, got $version" >&2
    exit 1
  fi
  version=$stripped_version
fi

app_choice=${COUNTERSIGN_APP:-}
if [ -n "$app_choice" ] && [ "$app_choice" != "0" ] && [ "$app_choice" != "1" ]; then
  echo "install: COUNTERSIGN_APP must be 0 or 1, got $app_choice" >&2
  exit 1
fi

setup_choice=${COUNTERSIGN_SETUP:-}
if [ -n "$setup_choice" ] && [ "$setup_choice" != "0" ] && [ "$setup_choice" != "1" ]; then
  echo "install: COUNTERSIGN_SETUP must be 0 or 1, got $setup_choice" >&2
  exit 1
fi

if [ -n "${COUNTERSIGN_BASE_URL:-}" ]; then
  base_url=$COUNTERSIGN_BASE_URL
elif [ -n "$version" ]; then
  base_url="https://github.com/Gord1y/countersign/releases/download/v$version"
else
  base_url="https://github.com/Gord1y/countersign/releases/latest/download"
fi

if [ -n "$version" ]; then
  tarball_name="countersign-$version-macos.tar.gz"
else
  tarball_name="countersign-macos.tar.gz"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/countersign-install.XXXXXX")
trap 'rm -rf "$work"' EXIT

tarball="$work/$tarball_name"
checksum="$work/$tarball_name.sha256"
curl -fsSL "$base_url/$tarball_name" -o "$tarball"
curl -fsSL "$base_url/$tarball_name.sha256" -o "$checksum"

(cd "$work" && shasum -a 256 -c "$(basename "$checksum")")

extract_dir="$work/extract"
mkdir -p "$extract_dir"
tar -xzf "$tarball" -C "$extract_dir"
release_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -z "$release_dir" ]; then
  echo "install: $tarball_name did not contain a release folder" >&2
  exit 1
fi
installed_version=${release_dir##*/}
installed_version=${installed_version#countersign-}

bin_dir="$HOME/.local/bin"
mkdir -p "$bin_dir"
cp "$release_dir/countersign" "$bin_dir/countersign.new"
chmod 755 "$bin_dir/countersign.new"
mv -f "$bin_dir/countersign.new" "$bin_dir/countersign"
echo "installed $bin_dir/countersign"

apps_dir="$HOME/Applications"
app_dir="$apps_dir/Countersign.app"
app_existed_before=0
if [ -e "$app_dir" ]; then
  app_existed_before=1
fi
app_replaced=0

install_app() {
  mkdir -p "$apps_dir"
  rm -rf "$app_dir"
  cp -R "$release_dir/Countersign.app" "$app_dir"
  echo "installed $app_dir"
  app_replaced=1
}

print_app_skip_hint() {
  echo "skipped the menu-bar app, add it later with:"
  echo "  curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | COUNTERSIGN_APP=1 sh"
}

if [ "$app_choice" = "1" ]; then
  install_app
elif [ "$app_choice" = "0" ]; then
  if [ -e "$app_dir" ]; then
    echo "$app_dir already exists, left as it is"
  else
    print_app_skip_hint
  fi
elif [ -e "$app_dir" ]; then
  install_app
elif (exec </dev/tty >/dev/tty) 2>/dev/null; then
  while :; do
    printf 'Install the menu-bar app too? [Y/n] ' >/dev/tty
    if read -r answer <"/dev/tty"; then
      case "$answer" in
      "" | [Yy] | [Yy][Ee][Ss])
        install_app
        break
        ;;
      [Nn] | [Nn][Oo])
        print_app_skip_hint
        break
        ;;
      *) ;;
      esac
    else
      printf '\n' >/dev/tty
      install_app
      break
    fi
  done
else
  install_app
fi

if [ "$app_replaced" = "1" ] && [ "$app_existed_before" = "1" ]; then
  if pgrep -f "$app_dir/Contents/MacOS/countersign" >/dev/null 2>&1; then
    echo "Countersign.app is still running the previous version; quit it from the menu bar and open it again"
  fi
fi

case ":$PATH:" in
*":$bin_dir:"*) ;;
*)
  echo "add $bin_dir to your PATH, for example:"
  echo "  export PATH=\"$bin_dir:\$PATH\""
  ;;
esac

echo "installed countersign $installed_version"

open_setup=0
if [ "$setup_choice" = "1" ]; then
  open_setup=1
elif [ "$setup_choice" = "0" ]; then
  open_setup=0
elif (exec </dev/tty >/dev/tty) 2>/dev/null; then
  while :; do
    printf 'Open Countersign now to set up your agents? [Y/n] ' >/dev/tty
    if read -r answer <"/dev/tty"; then
      case "$answer" in
      "" | [Yy] | [Yy][Ee][Ss])
        open_setup=1
        break
        ;;
      [Nn] | [Nn][Oo])
        open_setup=0
        break
        ;;
      *) ;;
      esac
    else
      printf '\n' >/dev/tty
      open_setup=1
      break
    fi
  done
fi

if [ "$open_setup" = "1" ] && [ -e "$app_dir" ]; then
  if open "$app_dir" --args --setup; then
    echo "opening Countersign to set up your agents"
  else
    echo "next: countersign setup"
  fi
elif [ "$open_setup" = "1" ]; then
  (nohup "$bin_dir/countersign" setup </dev/null >/dev/null 2>&1 &)
  echo "opening the Countersign setup window"
else
  echo "next: countersign setup"
fi
