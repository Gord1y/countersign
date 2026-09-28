#!/bin/sh
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$scripts/.." && pwd)
installer="$repo_root/install.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/test-install.XXXXXX")
trap 'rm -rf "$work"' EXIT
failures=0
setup_override=0

fail() {
  echo "test-install: $1" >&2
  failures=$((failures + 1))
}

make_fake_binary() {
  cat >"$1" <<'FAKE'
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "countersign 9.9.9"
fi
if [ "$1" = "setup" ]; then
  echo "setup-called" >"$HOME/setup-called"
fi
FAKE
  chmod 755 "$1"
}

fake_bin="$work/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/open" <<'FAKE'
#!/bin/sh
echo "$@" >"$HOME/open-called"
if [ -f "$HOME/open-fails" ]; then
  exit 1
fi
exit 0
FAKE
chmod 755 "$fake_bin/open"

cat >"$fake_bin/pgrep" <<'FAKE'
#!/bin/sh
echo "$@" >"$HOME/pgrep-called"
if [ -f "$HOME/pgrep-running" ]; then
  echo 4242
  exit 0
fi
exit 1
FAKE
chmod 755 "$fake_bin/pgrep"

pty_wrapper="$work/pty-wrapper.sh"
cat >"$pty_wrapper" <<'WRAP'
#!/bin/sh
set -eu
status=0
"$@" || status=$?
sleep 0.2
exit "$status"
WRAP
chmod 755 "$pty_wrapper"

wait_for_marker() {
  marker=$1
  tries=0
  while [ ! -f "$marker" ] && [ "$tries" -lt 200 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
  [ -f "$marker" ]
}

release_src="$work/release-src/countersign-9.9.9"
mkdir -p "$release_src/Countersign.app/Contents/MacOS"
make_fake_binary "$release_src/countersign"
make_fake_binary "$release_src/Countersign.app/Contents/MacOS/countersign"
echo "9.9.9" >"$release_src/Countersign.app/Contents/marker"
cp "$repo_root/LICENSE" "$release_src/LICENSE"
cp "$repo_root/README.md" "$release_src/README.md"

good_url_dir="$work/good-release"
mkdir -p "$good_url_dir"
(cd "$(dirname "$release_src")" && tar -czf "$good_url_dir/countersign-macos.tar.gz" "countersign-9.9.9")
(cd "$good_url_dir" && shasum -a 256 countersign-macos.tar.gz >countersign-macos.tar.gz.sha256)

bad_url_dir="$work/bad-release"
mkdir -p "$bad_url_dir"
cp "$good_url_dir/countersign-macos.tar.gz" "$bad_url_dir/countersign-macos.tar.gz"
zero_hash=$(printf '0%.0s' $(seq 1 64))
echo "$zero_hash  countersign-macos.tar.gz" >"$bad_url_dir/countersign-macos.tar.gz.sha256"

pinned_url_dir="$work/pinned-release"
mkdir -p "$pinned_url_dir"
(cd "$(dirname "$release_src")" && tar -czf "$pinned_url_dir/countersign-9.9.9-macos.tar.gz" "countersign-9.9.9")
(cd "$pinned_url_dir" && shasum -a 256 countersign-9.9.9-macos.tar.gz >countersign-9.9.9-macos.tar.gz.sha256)

run_install() {
  home_dir=$1
  base_url=$2
  path_value=${3:-$PATH}
  version_value=${4:-}
  app_value=${5:-1}
  env -i \
    HOME="$home_dir" \
    COUNTERSIGN_BASE_URL="$base_url" \
    COUNTERSIGN_VERSION="$version_value" \
    COUNTERSIGN_APP="$app_value" \
    COUNTERSIGN_SETUP="$setup_override" \
    PATH="$fake_bin:$path_value" \
    TMPDIR="${TMPDIR:-/tmp}" \
    "$installer"
}

run_install_no_tty() {
  home_dir=$1
  base_url=$2
  perl -MPOSIX -e 'my $pid = fork; if ($pid) { waitpid($pid, 0); exit($? >> 8) } POSIX::setsid(); exec @ARGV or exit 127' \
    env -i \
    HOME="$home_dir" \
    COUNTERSIGN_BASE_URL="$base_url" \
    COUNTERSIGN_SETUP="$setup_override" \
    PATH="$fake_bin:$PATH" \
    TMPDIR="${TMPDIR:-/tmp}" \
    "$installer"
}

run_install_pty() {
  home_dir=$1
  base_url=$2
  app_value=$3
  shift 3
  {
    for line in "$@"; do
      printf '%s\n' "$line"
    done
    sleep 1
  } | script -q /dev/null "$pty_wrapper" env -i \
    HOME="$home_dir" \
    COUNTERSIGN_BASE_URL="$base_url" \
    COUNTERSIGN_APP="$app_value" \
    COUNTERSIGN_SETUP="$setup_override" \
    PATH="$fake_bin:$PATH" \
    TMPDIR="${TMPDIR:-/tmp}" \
    "$installer"
}

home1="$work/home1"
mkdir -p "$home1"
out1="$work/out1"
if ! run_install "$home1" "file://$good_url_dir" >"$out1" 2>&1; then
  fail "fresh install: expected success: $(cat "$out1")"
fi
if [ ! -x "$home1/.local/bin/countersign" ]; then
  fail "fresh install: did not install the CLI"
elif [ "$("$home1/.local/bin/countersign" --version)" != "countersign 9.9.9" ]; then
  fail "fresh install: installed CLI did not run"
fi
mode=$(stat -f '%OLp' "$home1/.local/bin/countersign" 2>/dev/null || stat -c '%a' "$home1/.local/bin/countersign")
if [ "$mode" != "755" ]; then
  fail "fresh install: expected mode 755, got $mode"
fi
if [ ! -f "$home1/Applications/Countersign.app/Contents/marker" ]; then
  fail "fresh install: did not install the app"
fi
if ! grep -qF "next: countersign setup" "$out1"; then
  fail "fresh install: did not print the next step: $(cat "$out1")"
fi
if ! grep -qF 'add' "$out1" || ! grep -qF "$home1/.local/bin" "$out1"; then
  fail "fresh install: did not print a PATH hint: $(cat "$out1")"
fi
if ! grep -qF "installed countersign 9.9.9" "$out1"; then
  fail "fresh install: did not print the installed version: $(cat "$out1")"
fi

home2="$work/home2"
mkdir -p "$home2/Applications/Countersign.app/Contents"
echo "stale" >"$home2/Applications/Countersign.app/Contents/marker"
out2="$work/out2"
if ! run_install "$home2" "file://$good_url_dir" >"$out2" 2>&1; then
  fail "replace existing: expected success: $(cat "$out2")"
fi
if [ "$(cat "$home2/Applications/Countersign.app/Contents/marker")" != "9.9.9" ]; then
  fail "replace existing: old app was not replaced"
fi

home3="$work/home3"
mkdir -p "$home3"
out3="$work/out3"
if run_install "$home3" "file://$bad_url_dir" >"$out3" 2>&1; then
  fail "checksum mismatch: expected failure"
fi
if [ -e "$home3/.local/bin/countersign" ] || [ -e "$home3/Applications/Countersign.app" ]; then
  fail "checksum mismatch: installed something despite the failed check"
fi

home4="$work/home4"
mkdir -p "$home4/.local/bin"
out4="$work/out4"
if ! run_install "$home4" "file://$good_url_dir" "$home4/.local/bin:$PATH" >"$out4" 2>&1; then
  fail "PATH already set: expected success: $(cat "$out4")"
fi
if grep -qF 'add' "$out4"; then
  fail "PATH already set: printed a PATH hint anyway: $(cat "$out4")"
fi

home5="$work/home5"
mkdir -p "$home5"
out5="$work/out5"
if ! run_install "$home5" "file://$pinned_url_dir" "$PATH" "9.9.9" >"$out5" 2>&1; then
  fail "pinned version: expected success: $(cat "$out5")"
fi
if [ ! -x "$home5/.local/bin/countersign" ]; then
  fail "pinned version: did not install the CLI"
fi
if ! grep -qF "installed countersign 9.9.9" "$out5"; then
  fail "pinned version: did not print the installed version: $(cat "$out5")"
fi

home6="$work/home6"
mkdir -p "$home6"
out6="$work/out6"
if ! run_install "$home6" "file://$pinned_url_dir" "$PATH" "v9.9.9" >"$out6" 2>&1; then
  fail "pinned version with a leading v: expected success: $(cat "$out6")"
fi
if [ ! -x "$home6/.local/bin/countersign" ]; then
  fail "pinned version with a leading v: did not install the CLI"
fi
if ! grep -qF "installed countersign 9.9.9" "$out6"; then
  fail "pinned version with a leading v: did not print the installed version: $(cat "$out6")"
fi

home7="$work/home7"
mkdir -p "$home7"
out7="$work/out7"
if run_install "$home7" "file://$pinned_url_dir" "$PATH" "9.9" >"$out7" 2>&1; then
  fail "malformed version: expected failure"
fi
if [ -e "$home7/.local/bin/countersign" ] || [ -e "$home7/Applications/Countersign.app" ]; then
  fail "malformed version: installed something despite the malformed version"
fi
if ! grep -qF "MAJOR.MINOR.PATCH" "$out7"; then
  fail "malformed version: did not explain the expected format: $(cat "$out7")"
fi

home8="$work/home8"
mkdir -p "$home8"
out8="$work/out8"
if ! run_install_no_tty "$home8" "file://$good_url_dir" >"$out8" 2>&1; then
  fail "no terminal, app unset: expected success: $(cat "$out8")"
fi
if [ ! -f "$home8/Applications/Countersign.app/Contents/marker" ]; then
  fail "no terminal, app unset: did not install the app: $(cat "$out8")"
fi

home9="$work/home9"
mkdir -p "$home9"
out9="$work/out9"
if ! run_install "$home9" "file://$good_url_dir" "$PATH" "" "0" >"$out9" 2>&1; then
  fail "app disabled, fresh: expected success: $(cat "$out9")"
fi
if [ ! -x "$home9/.local/bin/countersign" ]; then
  fail "app disabled, fresh: did not install the CLI"
fi
if [ -e "$home9/Applications/Countersign.app" ]; then
  fail "app disabled, fresh: installed the app anyway"
fi
if ! grep -qF "skipped the menu-bar app" "$out9"; then
  fail "app disabled, fresh: did not print the skip line: $(cat "$out9")"
fi

home10="$work/home10"
mkdir -p "$home10/Applications/Countersign.app/Contents"
echo "stale" >"$home10/Applications/Countersign.app/Contents/marker"
out10="$work/out10"
if ! run_install "$home10" "file://$good_url_dir" "$PATH" "" "0" >"$out10" 2>&1; then
  fail "app disabled, existing app: expected success: $(cat "$out10")"
fi
if [ "$(cat "$home10/Applications/Countersign.app/Contents/marker")" != "stale" ]; then
  fail "app disabled, existing app: touched the existing app"
fi
if ! grep -qF "left as it is" "$out10"; then
  fail "app disabled, existing app: did not say the app was left as it is: $(cat "$out10")"
fi

home11="$work/home11"
mkdir -p "$home11"
out11="$work/out11"
run_install_pty "$home11" "file://$good_url_dir" "1" >"$out11" 2>&1 || true
if [ ! -f "$home11/Applications/Countersign.app/Contents/marker" ]; then
  fail "app enabled, pty: did not install the app: $(cat "$out11")"
fi
if grep -qF "Install the menu-bar app too?" "$out11"; then
  fail "app enabled, pty: printed the prompt anyway: $(cat "$out11")"
fi

home12="$work/home12"
mkdir -p "$home12"
out12="$work/out12"
if run_install "$home12" "file://$good_url_dir" "$PATH" "" "yes" >"$out12" 2>&1; then
  fail "malformed app value: expected failure"
fi
if [ -e "$home12/.local/bin/countersign" ] || [ -e "$home12/Applications/Countersign.app" ]; then
  fail "malformed app value: installed something despite the malformed value"
fi
if ! grep -qF "COUNTERSIGN_APP must be 0 or 1" "$out12"; then
  fail "malformed app value: did not explain the expected values: $(cat "$out12")"
fi

home13="$work/home13"
mkdir -p "$home13"
out13="$work/out13"
run_install_pty "$home13" "file://$good_url_dir" "" "n" >"$out13" 2>&1 || true
if [ -e "$home13/Applications/Countersign.app" ]; then
  fail "pty answers n: installed the app anyway: $(cat "$out13")"
fi
if ! grep -qF "Install the menu-bar app too?" "$out13"; then
  fail "pty answers n: did not print the prompt: $(cat "$out13")"
fi
prompt_count13=$(grep -oF "Install the menu-bar app too?" "$out13" | wc -l | tr -d ' ')
if [ "$prompt_count13" != "1" ]; then
  fail "pty answers n: expected the prompt exactly once, got $prompt_count13: $(cat "$out13")"
fi

home14="$work/home14"
mkdir -p "$home14"
out14="$work/out14"
run_install_pty "$home14" "file://$good_url_dir" "" "" >"$out14" 2>&1 || true
if [ ! -f "$home14/Applications/Countersign.app/Contents/marker" ]; then
  fail "pty answers empty: did not install the app: $(cat "$out14")"
fi
prompt_count14=$(grep -oF "Install the menu-bar app too?" "$out14" | wc -l | tr -d ' ')
if [ "$prompt_count14" != "1" ]; then
  fail "pty answers empty: expected the prompt exactly once, got $prompt_count14: $(cat "$out14")"
fi

home15="$work/home15"
mkdir -p "$home15"
out15="$work/out15"
run_install_pty "$home15" "file://$good_url_dir" "" "Y" >"$out15" 2>&1 || true
if [ ! -f "$home15/Applications/Countersign.app/Contents/marker" ]; then
  fail "pty answers Y: did not install the app: $(cat "$out15")"
fi
prompt_count15=$(grep -oF "Install the menu-bar app too?" "$out15" | wc -l | tr -d ' ')
if [ "$prompt_count15" != "1" ]; then
  fail "pty answers Y: expected the prompt exactly once, got $prompt_count15: $(cat "$out15")"
fi

home16="$work/home16"
mkdir -p "$home16"
out16="$work/out16"
run_install_pty "$home16" "file://$good_url_dir" "" "maybe" "n" >"$out16" 2>&1 || true
if [ -e "$home16/Applications/Countersign.app" ]; then
  fail "pty answers maybe then n: installed the app anyway: $(cat "$out16")"
fi
prompt_count=$(grep -oF "Install the menu-bar app too?" "$out16" | wc -l | tr -d ' ')
if [ "$prompt_count" -lt 2 ]; then
  fail "pty answers maybe then n: expected to be asked again after the unrecognized answer, asked $prompt_count times: $(cat "$out16")"
fi

home17="$work/home17"
mkdir -p "$home17/Applications/Countersign.app/Contents"
echo "stale" >"$home17/Applications/Countersign.app/Contents/marker"
out17="$work/out17"
run_install_pty "$home17" "file://$good_url_dir" "" >"$out17" 2>&1 || true
if [ "$(cat "$home17/Applications/Countersign.app/Contents/marker")" != "9.9.9" ]; then
  fail "app unset, existing app, pty: did not update the app: $(cat "$out17")"
fi
if grep -qF "Install the menu-bar app too?" "$out17"; then
  fail "app unset, existing app, pty: printed the prompt anyway: $(cat "$out17")"
fi

home18="$work/home18"
mkdir -p "$home18"
out18="$work/out18"
setup_override=
run_install_pty "$home18" "file://$good_url_dir" "1" >"$out18" 2>&1 || true
setup_override=0
if ! wait_for_marker "$home18/open-called"; then
  fail "pty, setup unset, app installed: fake open was not called: $(cat "$out18")"
elif ! grep -qF "$home18/Applications/Countersign.app" "$home18/open-called"; then
  fail "pty, setup unset, app installed: fake open was not called with the app path"
fi
if ! grep -qF "opening Countersign to set up your agents" "$out18"; then
  fail "pty, setup unset, app installed: did not print the app open line: $(cat "$out18")"
fi
if grep -qF "next: countersign setup" "$out18"; then
  fail "pty, setup unset, app installed: printed next: anyway: $(cat "$out18")"
fi

home19="$work/home19"
mkdir -p "$home19"
out19="$work/out19"
setup_override=
run_install_pty "$home19" "file://$good_url_dir" "0" >"$out19" 2>&1 || true
setup_override=0
if ! wait_for_marker "$home19/setup-called"; then
  fail "pty, setup unset, app disabled: fake countersign setup was not called: $(cat "$out19")"
fi
if ! grep -qF "opening Countersign Settings to set up your agents" "$out19"; then
  fail "pty, setup unset, app disabled: did not print the CLI open line: $(cat "$out19")"
fi
if grep -qF "next: countersign setup" "$out19"; then
  fail "pty, setup unset, app disabled: printed next: anyway: $(cat "$out19")"
fi

home20="$work/home20"
mkdir -p "$home20"
out20="$work/out20"
setup_override=
if ! run_install_no_tty "$home20" "file://$good_url_dir" >"$out20" 2>&1; then
  fail "no terminal, setup unset: expected success: $(cat "$out20")"
fi
setup_override=0
if [ -f "$home20/open-called" ] || [ -f "$home20/setup-called" ]; then
  fail "no terminal, setup unset: opened something anyway: $(cat "$out20")"
fi
if ! grep -qF "next: countersign setup" "$out20"; then
  fail "no terminal, setup unset: did not print the next step: $(cat "$out20")"
fi

home21="$work/home21"
mkdir -p "$home21"
out21="$work/out21"
run_install_pty "$home21" "file://$good_url_dir" "1" >"$out21" 2>&1 || true
if [ -f "$home21/open-called" ] || [ -f "$home21/setup-called" ]; then
  fail "pty, setup disabled: opened something anyway: $(cat "$out21")"
fi
if ! grep -qF "next: countersign setup" "$out21"; then
  fail "pty, setup disabled: did not print the next step: $(cat "$out21")"
fi
if grep -qF "Open Countersign now to set up your agents?" "$out21"; then
  fail "pty, setup disabled: printed the setup question anyway: $(cat "$out21")"
fi

home22="$work/home22"
mkdir -p "$home22"
out22="$work/out22"
setup_override=1
if ! run_install_no_tty "$home22" "file://$good_url_dir" >"$out22" 2>&1; then
  fail "no terminal, setup forced on: expected success: $(cat "$out22")"
fi
setup_override=0
if ! wait_for_marker "$home22/open-called"; then
  fail "no terminal, setup forced on: fake open was not called: $(cat "$out22")"
fi
if ! grep -qF "opening Countersign to set up your agents" "$out22"; then
  fail "no terminal, setup forced on: did not print the app open line: $(cat "$out22")"
fi

home23="$work/home23"
mkdir -p "$home23"
out23="$work/out23"
setup_override=yes
if run_install "$home23" "file://$good_url_dir" >"$out23" 2>&1; then
  fail "malformed setup value: expected failure"
fi
setup_override=0
if [ -e "$home23/.local/bin/countersign" ] || [ -e "$home23/Applications/Countersign.app" ]; then
  fail "malformed setup value: installed something despite the malformed value"
fi
if ! grep -qF "COUNTERSIGN_SETUP must be 0 or 1" "$out23"; then
  fail "malformed setup value: did not explain the expected values: $(cat "$out23")"
fi

home24="$work/home24"
mkdir -p "$home24/Applications/Countersign.app/Contents"
echo "stale" >"$home24/Applications/Countersign.app/Contents/marker"
touch "$home24/pgrep-running"
out24="$work/out24"
if ! run_install "$home24" "file://$good_url_dir" >"$out24" 2>&1; then
  fail "app replaced while running: expected success: $(cat "$out24")"
fi
if [ "$(cat "$home24/Applications/Countersign.app/Contents/marker")" != "9.9.9" ]; then
  fail "app replaced while running: old app was not replaced"
fi
if ! grep -qF "Countersign.app is still running the previous version" "$out24"; then
  fail "app replaced while running: did not print the still-running warning: $(cat "$out24")"
fi

home25="$work/home25"
mkdir -p "$home25"
touch "$home25/open-fails"
out25="$work/out25"
setup_override=
if ! run_install_pty "$home25" "file://$good_url_dir" "1" >"$out25" 2>&1; then
  fail "pty, open fails: expected success: $(cat "$out25")"
fi
setup_override=0
if ! grep -qF "next: countersign setup" "$out25"; then
  fail "pty, open fails: did not print the next step: $(cat "$out25")"
fi
if grep -qF "opening Countersign" "$out25"; then
  fail "pty, open fails: printed an opening line anyway: $(cat "$out25")"
fi

home26="$work/home26"
mkdir -p "$home26"
out26="$work/out26"
if ! run_install_pty "$home26" "file://$good_url_dir" "" >"$out26" 2>&1; then
  fail "pty no answer at all: expected success: $(cat "$out26")"
fi
if [ ! -f "$home26/Applications/Countersign.app/Contents/marker" ]; then
  fail "pty no answer at all: did not install the app: $(cat "$out26")"
fi
prompt_count26=$(grep -oF "Install the menu-bar app too?" "$out26" | wc -l | tr -d ' ')
if [ "$prompt_count26" != "1" ]; then
  fail "pty no answer at all: expected the prompt exactly once, got $prompt_count26: $(cat "$out26")"
fi

home27="$work/home27"
mkdir -p "$home27"
out27="$work/out27"
setup_override=
run_install_pty "$home27" "file://$good_url_dir" "1" "n" >"$out27" 2>&1 || true
setup_override=0
if [ -f "$home27/open-called" ] || [ -f "$home27/setup-called" ]; then
  fail "pty, setup answered n: opened something anyway: $(cat "$out27")"
fi
if ! grep -qF "next: countersign setup" "$out27"; then
  fail "pty, setup answered n: did not print the next step: $(cat "$out27")"
fi
if ! grep -qF "Open Countersign now to set up your agents?" "$out27"; then
  fail "pty, setup answered n: did not print the question: $(cat "$out27")"
fi

home28="$work/home28"
mkdir -p "$home28"
out28="$work/out28"
setup_override=
run_install_pty "$home28" "file://$good_url_dir" "1" "" >"$out28" 2>&1 || true
setup_override=0
if ! wait_for_marker "$home28/open-called"; then
  fail "pty, setup answered empty: fake open was not called: $(cat "$out28")"
fi
if ! grep -qF "opening Countersign to set up your agents" "$out28"; then
  fail "pty, setup answered empty: did not print the app open line: $(cat "$out28")"
fi

home29="$work/home29"
mkdir -p "$home29"
out29="$work/out29"
setup_override=
run_install_pty "$home29" "file://$good_url_dir" "1" >"$out29" 2>&1 || true
setup_override=0
if ! wait_for_marker "$home29/open-called"; then
  fail "pty, setup EOF: fake open was not called: $(cat "$out29")"
fi
if ! grep -qF "opening Countersign to set up your agents" "$out29"; then
  fail "pty, setup EOF: did not print the app open line: $(cat "$out29")"
fi

home31="$work/home31"
mkdir -p "$home31"
out31="$work/out31"
setup_override=1
run_install_pty "$home31" "file://$good_url_dir" "1" >"$out31" 2>&1 || true
setup_override=0
if grep -qF "Open Countersign now to set up your agents?" "$out31"; then
  fail "pty, setup forced on: printed the question anyway: $(cat "$out31")"
fi
if ! wait_for_marker "$home31/open-called"; then
  fail "pty, setup forced on: fake open was not called: $(cat "$out31")"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-install: $failures failed" >&2
  exit 1
fi
echo "test-install: ok"
