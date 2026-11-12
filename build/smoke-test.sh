#!/usr/bin/env bash
# Smoke test of an IFW prefix built by build-ifw.sh (or unpacked from a published archive):
#   - every tool is there; on macOS each is arm64-only
#   - binarycreator --help and installerbase --version run and report the expected versions
#   - binarycreator builds a small offline installer, which installs one file headlessly
#
# Usage: smoke-test.sh <prefix> [work dir]
# On Linux without a display the installer runs under xvfb-run when it is installed.
set -euo pipefail

fail() {
  echo "smoke-test: FAIL: $1" >&2
  exit 1
}

[ "$#" -ge 1 ] || { echo "usage: smoke-test.sh <prefix> [work dir]" >&2; exit 2; }
prefix=$(cd "$1" && pwd)
work=${2:-$(mktemp -d)}
mkdir -p "$work"
work=$(cd "$work" && pwd)

case "$(uname -s)" in
  Darwin) platform=macos ;;
  Linux) platform=linux ;;
  MINGW* | MSYS*) platform=windows ;;
  *) fail "unsupported system: $(uname -s)" ;;
esac
exe=""
[ "$platform" = windows ] && exe=.exe
bin=$prefix/bin
ifw=$(sed -n 's/^ifw=//p' "$prefix/VERSIONS")
qt=$(sed -n 's/^qt=//p' "$prefix/VERSIONS")
[ -n "$ifw" ] && [ -n "$qt" ] || fail "VERSIONS lacks ifw= or qt="
echo "smoke-test: $(tr '\n' ' ' < "$prefix/VERSIONS")"

for tool in binarycreator installerbase archivegen repogen devtool; do
  [ -f "$bin/$tool$exe" ] || fail "missing $bin/$tool$exe"
  [ "$platform" = windows ] || [ -x "$bin/$tool" ] || fail "not executable: $bin/$tool"
  if [ "$platform" = macos ]; then
    archs=$(lipo -archs "$bin/$tool")
    echo "smoke-test: lipo -archs $tool: $archs"
    [ "$archs" = arm64 ] || fail "$tool is not arm64-only: $archs"
  fi
done

out=$("$bin/binarycreator$exe" --help 2>&1 || true)
echo "$out" | head -5
echo "$out" | grep -q 'binarycreator' || fail "binarycreator --help printed no usage"

out=$("$bin/installerbase$exe" --version 2>&1) || fail "installerbase --version failed: $out"
echo "$out"
echo "$out" | grep -q "IFW Version: $ifw, built with Qt $qt\." || fail "installerbase --version does not report IFW $ifw / Qt $qt"
echo "$out" | grep -q 'liblzma' || fail "libarchive in installerbase lacks liblzma"
echo "$out" | grep -q 'bz2lib' || fail "libarchive in installerbase lacks bzip2"

# A one-component offline installer, installed headlessly into a fresh folder.
rm -rf "$work/config" "$work/packages" "$work/out" "$work/root"
mkdir -p "$work/config" "$work/packages/org.example.smoke/meta" "$work/packages/org.example.smoke/data" "$work/out"
cat > "$work/config/config.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Installer>
    <Name>IFW smoke test</Name>
    <Version>1.0.0</Version>
    <Title>IFW smoke test</Title>
    <Publisher>qt-ifw-asset</Publisher>
    <StartMenuDir>IFW smoke test</StartMenuDir>
    <TargetDir>@HomeDir@/ifw-smoke-test</TargetDir>
</Installer>
EOF
cat > "$work/packages/org.example.smoke/meta/package.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Package>
    <DisplayName>Smoke test</DisplayName>
    <Description>One file</Description>
    <Version>1.0.0</Version>
    <ReleaseDate>2026-01-01</ReleaseDate>
    <Default>true</Default>
</Package>
EOF
echo "qt-ifw-asset smoke test" > "$work/packages/org.example.smoke/data/smoke.txt"

native() {
  if [ "$platform" = windows ]; then cygpath -w "$1"; else echo "$1"; fi
}

(cd "$work" && "$bin/binarycreator$exe" --offline-only -c config/config.xml -p packages out/smoke-installer) ||
  fail "binarycreator could not build an installer"
case "$platform" in
  macos) installer="$work/out/smoke-installer.app/Contents/MacOS/smoke-installer" ;;
  *) installer="$work/out/smoke-installer$exe" ;;
esac
[ -f "$installer" ] || fail "binarycreator made no installer at $installer"
# binarycreator invalidates installerbase's ad-hoc signature; arm64 macOS kills unsigned code.
[ "$platform" = macos ] && codesign --force --deep --sign - "$work/out/smoke-installer.app"
ls -l "$installer"

run=()
# macOS has no timeout(1) unless coreutils are installed.
command -v timeout >/dev/null && run=(timeout 600)
if [ "$platform" = linux ] && [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
  run=(${run[@]+"${run[@]}"} xvfb-run -a)
fi
# (The ${run[@]+...} form keeps an empty array usable under set -u in bash 3.2.)
${run[@]+"${run[@]}"} "$installer" install --root "$(native "$work/root")" --accept-licenses \
  --default-answer --confirm-command || fail "the installer did not install"
[ "$(cat "$work/root/smoke.txt")" = "qt-ifw-asset smoke test" ] || fail "installed file missing or wrong"
echo "smoke-test: OK ($platform, IFW $ifw, Qt $qt)"
