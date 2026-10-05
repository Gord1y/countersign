#!/bin/sh
set -eu

here=$(cd "$(dirname "$0")" && pwd -P)
root=$(cd "$here/../.." && pwd -P)
demo="$here/demo"
out=${1:-"$root/.build/screenshots"}
countersign="$root/.build/debug/countersign"
settings_readme_crop_height=1092
settings_rules_readme_crop_height=1490
card_tile_width=1200

swift build --package-path "$root" --quiet
mkdir -p "$out"
work=$(mktemp -d "${TMPDIR:-/tmp}/screenshots.XXXXXX")
demo_home=$(mktemp -d "/tmp/countersign-screenshots.XXXXXX")
trap 'rm -rf "$work" "$demo_home"' EXIT
demo_replacement=$(printf '%s' "$demo" | sed 's/[&|\\]/\\&/g')
countersign_resolved="$(cd "$(dirname "$countersign")" && pwd -P)/$(basename "$countersign")"
executable_replacement=$(printf '%s' "$countersign_resolved" | sed 's/[&|\\]/\\&/g')

for request in "$here"/requests/*.json; do
  name=$(basename "$request" .json)
  host=${name%%-*}
  sed "s|{{DEMO}}|$demo_replacement|g" "$request" >"$work/$name.json"
  if grep -q '{{' "$work/$name.json"; then
    echo "render: $request has a placeholder other than {{DEMO}}" >&2
    exit 1
  fi
  if [ "$host" = "claude" ]; then
    transcript=$(plutil -extract transcript_path raw -o - "$work/$name.json" 2>/dev/null) || transcript=""
    if [ -n "$transcript" ] && [ ! -f "$transcript" ]; then
      echo "render: $request points at a missing transcript; the panel would show the chat-tracking warning" >&2
      exit 1
    fi
  fi
  case $name in
  claude-edit) waiting=2 ;;
  *) waiting=0 ;;
  esac
  for appearance in light dark; do
    png="$out/$name-$appearance.png"
    "$countersign" snapshot "$work/$name.json" --host "$host" --waiting "$waiting" \
      --appearance "$appearance" -o "$png"
    echo "$png"
  done
done

home_files=$(cd "$demo/home" && find . -type f)
for relative in $home_files; do
  mkdir -p "$demo_home/$(dirname "$relative")"
  sed "s|{{EXECUTABLE}}|$executable_replacement|g" "$demo/home/$relative" >"$demo_home/$relative"
  if grep -q '{{' "$demo_home/$relative"; then
    echo "render: $demo/home/$relative has a placeholder other than {{EXECUTABLE}}" >&2
    exit 1
  fi
done

for appearance in light dark; do
  png="$out/settings-$appearance.png"
  "$countersign" snapshot --settings --home "$demo_home" --status active \
    --appearance "$appearance" -o "$png"
  echo "$png"
  readme_png="$out/settings-$appearance-readme.png"
  swift "$here/crop-top.swift" "$png" "$settings_readme_crop_height" "$readme_png"
  echo "$readme_png"
done

for appearance in light dark; do
  for level in soft status insist; do
    png="$out/context-$level-$appearance.png"
    "$countersign" snapshot --test-panel context --checkpoint-level "$level" \
      --appearance "$appearance" -o "$png"
    echo "$png"
  done
  png="$out/settings-rules-$appearance.png"
  "$countersign" snapshot --settings --home "$demo_home" --status active --tab rules \
    --appearance "$appearance" -o "$png"
  echo "$png"
  readme_png="$out/settings-rules-$appearance-readme.png"
  swift "$here/crop-top.swift" "$png" "$settings_rules_readme_crop_height" "$readme_png"
  echo "$readme_png"
  png="$out/notice-$appearance.png"
  "$countersign" snapshot --waiting-notice codex --project shop-api \
    --appearance "$appearance" -o "$png"
  echo "$png"
  png="$out/approval-card-$appearance.png"
  "$countersign" snapshot --approval-card cursor --project shop-api \
    --appearance "$appearance" -o "$png"
  echo "$png"
done

for pair in \
  "edit:claude-edit-dark" \
  "command:claude-command-dark" \
  "questions:claude-questions-dark" \
  "plan:claude-plan-dark" \
  "codex:codex-patch-dark" \
  "cursor:cursor-command-dark" \
  "antigravity:antigravity-command-dark" \
  "checkpoint:context-insist-dark" \
  "rules:settings-rules-dark-readme"; do
  name=${pair%%:*}
  source=${pair#*:}
  tile="$out/tile-$name.jpg"
  swift "$here/compose-tile.swift" "$out/$source.png" "$tile"
  echo "$tile"
done

for card in notice approval-card; do
  sips --resampleWidth "$card_tile_width" "$out/$card-dark.png" --out "$work/$card-large.png" \
    >/dev/null
done
swift "$here/compose-stack.swift" "$work/notice-large.png" "$work/approval-card-large.png" \
  "$work/cards-stack.png"
cards_tile="$out/tile-cards.jpg"
swift "$here/compose-tile.swift" "$work/cards-stack.png" "$cards_tile"
echo "$cards_tile"

settings_tile="$out/tile-settings.jpg"
swift "$here/compose-tile.swift" "$out/settings-dark-readme.png" "$settings_tile"
echo "$settings_tile"
