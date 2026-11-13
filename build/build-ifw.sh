#!/usr/bin/env bash
# Build the Qt Installer Framework against a static Qt for the platform this runs on, so the
# installers it creates run without any Qt libraries installed.
#
#   macOS arm64    (Xcode command line tools)
#   Linux x86_64   (GCC; the X11/xcb development packages listed in the README)
#   Windows x86_64 (Git Bash in an MSVC developer environment: cl.exe on PATH, e.g. after
#                   ilammy/msvc-dev-cmd; static MSVC runtime)
#
# Usage: build-ifw.sh <prefix>
#   Installs binarycreator, installerbase, archivegen, repogen and devtool into <prefix>/bin,
#   the licenses of everything linked in into <prefix>/licenses, and <prefix>/VERSIONS.
#
# Environment:
#   IFW_BUILD_DIR  work folder (downloads, sources, static Qt); default <repo>/target/ifw-build.
#                  Keep it short on Windows (e.g. C:/w): Qt's build tree has long paths.
#   IFW_JOBS       parallel build jobs; default the number of CPUs.
#
# Pinned sources (checked against SHA-256): Qt Installer Framework 4.11.0, Qt 6.9.3 (qtbase,
# qtdeclarative, qttools, qt5compat), xz 5.8.1; on Linux and Windows also bzip2 1.0.8; on
# Windows also zlib 1.3.1 and jom 1.1.4 (parallel nmake).
set -euo pipefail

IFW_VERSION=4.11.0
QT_VERSION=6.9.3
XZ_VERSION=5.8.1
BZIP2_VERSION=1.0.8
ZLIB_VERSION=1.3.1
JOM_VERSION=1.1.4

fail() {
  echo "build-ifw: $1" >&2
  exit 1
}

step() {
  echo "build-ifw: $1 ($(date -u +%H:%M:%S))"
}

[ "$#" -eq 1 ] || { echo "usage: build-ifw.sh <prefix>" >&2; exit 2; }

case "$(uname -s)" in
  Darwin) platform=macos ;;
  Linux) platform=linux ;;
  MINGW* | MSYS*) platform=windows ;;
  *) fail "unsupported system: $(uname -s)" ;;
esac
arch=$(uname -m)
case "$platform-$arch" in
  macos-arm64 | linux-x86_64 | windows-x86_64) ;;
  *) fail "unsupported platform: $platform $arch (macOS arm64, Linux x86_64, Windows x86_64)" ;;
esac

repo=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$1"
prefix=$(cd "$1" && pwd)
work=${IFW_BUILD_DIR:-$repo/target/ifw-build}
mkdir -p "$work/dl"
work=$(cd "$work" && pwd)

case "$platform" in
  macos) jobs=${IFW_JOBS:-$(sysctl -n hw.ncpu)} ;;
  *) jobs=${IFW_JOBS:-$(nproc)} ;;
esac

exe=""
if [ "$platform" = windows ]; then
  exe=.exe
  command -v cl.exe >/dev/null || fail "cl.exe not on PATH: run in an MSVC developer environment"
  # Git Bash puts /usr/bin first, and its link.exe would shadow MSVC's linker under nmake/jom.
  PATH="$(dirname "$(command -v cl.exe)"):$PATH"
  export PATH
fi

# Native path for tools that are not MSYS programs (cmake, qmake, the compiler); forward slashes.
native() {
  if [ "$platform" = windows ]; then cygpath -m "$1"; else echo "$1"; fi
}

sha256_ok() { # <sha> <file>
  if command -v sha256sum >/dev/null; then
    echo "$1  $2" | sha256sum -c - >/dev/null 2>&1
  else
    echo "$1  $2" | shasum -a 256 -c - >/dev/null 2>&1
  fi
}

qt_url=https://download.qt.io/archive/qt/${QT_VERSION%.*}/$QT_VERSION/submodules
ifw_url=https://download.qt.io/official_releases/qt-installer-framework/$IFW_VERSION
xz_url=https://github.com/tukaani-project/xz/releases/download/v$XZ_VERSION
bzip2_url=https://sourceware.org/pub/bzip2
jom_url=https://download.qt.io/official_releases/jom
zlib_url=https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION

# name url sha256
sources="
qtbase-everywhere-src-$QT_VERSION.tar.xz $qt_url c5a1a2f660356ec081febfa782998ae5ddbc5925117e64f50e4be9cd45b8dc6e
qtdeclarative-everywhere-src-$QT_VERSION.tar.xz $qt_url 5a071b227229afbf5c976b7b59a0d850818d06ae861fcdf6d690351ca3f8a260
qttools-everywhere-src-$QT_VERSION.tar.xz $qt_url 0cf7ab0e975fc57f5ce1375576a0a76e9ede25e6b01db3cf2339cd4d9750b4e9
qt5compat-everywhere-src-$QT_VERSION.tar.xz $qt_url 091dac2124c2291c3566408720f89b1796cd458897c6acabd11f03976ad04461
installer-framework-everywhere-src-$IFW_VERSION.tar.xz $ifw_url 4abdad903a52b1c20bb46c715d7d12c65905791a3e366e574212fdd74cc47629
xz-$XZ_VERSION.tar.xz $xz_url 0b54f79df85912504de0b14aec7971e3f964491af1812d83447005807513cd9e
"
if [ "$platform" != macos ]; then
  # macOS has libbz2 in /usr/lib; elsewhere it is linked statically.
  sources="$sources
bzip2-$BZIP2_VERSION.tar.gz $bzip2_url ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269"
fi
if [ "$platform" = windows ]; then
  # libarchive includes <zlib.h>; Qt's bundled zlib is prefixed and exported for C++ only, and macOS
  # and Linux have a system zlib.
  sources="$sources
zlib-$ZLIB_VERSION.tar.gz $zlib_url 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
fi

# Downloads (kept between runs), verified, then unpacked into a fresh src/.
step "download sources"
rm -rf "$work/src"
mkdir -p "$work/src"
download() { # <name> <base url> <sha256>
  file="$work/dl/$1"
  if [ ! -f "$file" ] || ! sha256_ok "$3" "$file"; then
    curl -fsSL --retry 3 -o "$file.part" "$2/$1" || fail "download failed: $2/$1"
    mv "$file.part" "$file"
  fi
  sha256_ok "$3" "$file" || fail "checksum mismatch: $1"
}
echo "$sources" | while read -r name base sha; do
  [ -n "$name" ] || continue
  download "$name" "$base" "$sha"
  tar -xf "$work/dl/$name" -C "$work/src"
done
src=$work/src

if [ "$platform" = windows ]; then
  jom_zip="jom_${JOM_VERSION//./_}.zip"
  download "$jom_zip" "$jom_url" d533c1ef49214229681e90196ed2094691e8c4a0a0bef0b2c901debcb562682b
  rm -rf "$work/jom"
  mkdir -p "$work/jom"
  unzip -q "$work/dl/$jom_zip" -d "$work/jom"
  [ -f "$work/jom/jom.exe" ] || fail "jom.exe not in $jom_zip"
fi

# Nothing from Homebrew or /usr/local may end up in the macOS binaries.
cmake_args=""
if [ "$platform" = macos ]; then
  # Qt 6.9 supports macOS 12 and later.
  export MACOSX_DEPLOYMENT_TARGET=12.0
  export PKG_CONFIG_LIBDIR=/nonexistent
  unset PKG_CONFIG_PATH CMAKE_PREFIX_PATH
  cmake_args="-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local"
fi

# xz: libarchive in IFW needs liblzma; link it statically.
step "xz $XZ_VERSION"
xz_prefix=$work/xz
rm -rf "$xz_prefix" "$work/xz-build"
if [ "$platform" = windows ]; then
  cmake -S "$(native "$src/xz-$XZ_VERSION")" -B "$(native "$work/xz-build")" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DXZ_NLS=OFF -DXZ_DOC=OFF \
    -DXZ_TOOL_XZ=OFF -DXZ_TOOL_XZDEC=OFF -DXZ_TOOL_LZMADEC=OFF -DXZ_TOOL_LZMAINFO=OFF \
    -DXZ_TOOL_SCRIPTS=OFF -DXZ_TOOL_SYMLINKS=OFF -DXZ_TOOL_SYMLINKS_LZMA=OFF \
    -DCMAKE_INSTALL_PREFIX="$(native "$xz_prefix")" >/dev/null
  cmake --build "$(native "$work/xz-build")" --parallel "$jobs" >/dev/null
  cmake --install "$(native "$work/xz-build")" >/dev/null
  lzma_lib=$(find "$xz_prefix/lib" -maxdepth 1 -iname '*lzma*.lib' | head -1)
else
  (
    cd "$src/xz-$XZ_VERSION"
    cflags="-O2"
    [ "$platform" = macos ] && cflags="-O2 -arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
    [ "$platform" = linux ] && cflags="-O2 -fPIC"
    ./configure --prefix="$xz_prefix" --enable-static --disable-shared --disable-xz --disable-xzdec \
      --disable-lzmadec --disable-lzmainfo --disable-lzma-links --disable-scripts --disable-doc \
      --disable-nls CFLAGS="$cflags" >/dev/null
    make -j"$jobs" >/dev/null
    make install >/dev/null
  )
  lzma_lib=$xz_prefix/lib/liblzma.a
fi
[ -n "$lzma_lib" ] && [ -f "$lzma_lib" ] || fail "static liblzma not built"

# bzip2 (Linux, Windows): the library part only, compiled directly.
bz_prefix=$work/bzip2
bz_lib=""
if [ "$platform" != macos ]; then
  step "bzip2 $BZIP2_VERSION"
  rm -rf "$bz_prefix"
  mkdir -p "$bz_prefix/lib" "$bz_prefix/include"
  (
    cd "$src/bzip2-$BZIP2_VERSION"
    objs="blocksort huffman crctable randtable compress decompress bzlib"
    if [ "$platform" = windows ]; then
      for o in $objs; do
        cl.exe -nologo -c -O2 -MT -D_FILE_OFFSET_BITS=64 "$o.c" >/dev/null
      done
      lib.exe -nologo -OUT:"$(native "$bz_prefix/lib/libbz2.lib")" $(for o in $objs; do echo "$o.obj"; done)
    else
      for o in $objs; do
        cc -c -O2 -fPIC -D_FILE_OFFSET_BITS=64 "$o.c"
      done
      ar rcs "$bz_prefix/lib/libbz2.a" $(for o in $objs; do echo "$o.o"; done)
    fi
    cp bzlib.h "$bz_prefix/include/"
  )
  bz_lib=$(ls "$bz_prefix"/lib/libbz2.*)
fi

# zlib (Windows): the library only, compiled directly.
zlib_prefix=$work/zlib
zlib_lib=""
if [ "$platform" = windows ]; then
  step "zlib $ZLIB_VERSION"
  rm -rf "$zlib_prefix"
  mkdir -p "$zlib_prefix/lib" "$zlib_prefix/include"
  (
    cd "$src/zlib-$ZLIB_VERSION"
    objs="adler32 compress crc32 deflate gzclose gzlib gzread gzwrite infback inffast inflate inftrees trees uncompr zutil"
    for o in $objs; do
      cl.exe -nologo -c -O2 -MT -D_CRT_SECURE_NO_DEPRECATE -D_CRT_NONSTDC_NO_DEPRECATE "$o.c" >/dev/null
    done
    lib.exe -nologo -OUT:"$(native "$zlib_prefix/lib/zlib.lib")" $(for o in $objs; do echo "$o.obj"; done)
    cp zlib.h zconf.h "$zlib_prefix/include/"
  )
  zlib_lib=$zlib_prefix/lib/zlib.lib
fi

# Static Qt: the options IFW's INSTALL recommends for each platform, plus bundled third-party
# libraries, so no external library is picked up (Linux keeps the system X11/xcb, fontconfig and
# FreeType libraries a desktop has).
qt_prefix=$work/qt
rm -rf "$qt_prefix" "$work/qt-build"
mkdir -p "$work/qt-build"

qt_config="-release -static -nomake examples -nomake tests -accessibility
  -qt-zlib -qt-libpng -qt-libjpeg -qt-pcre -qt-harfbuzz -qt-doubleconversion
  -no-icu -no-openssl -no-zstd -no-glib -no-dbus -no-cups -no-sql-sqlite"
case "$platform" in
  macos) qt_config="$qt_config -no-pkg-config -no-freetype" ;;
  linux)
    qt_config="$qt_config -xcb -xcb-xlib -bundled-xcb-xinput -fontconfig -system-freetype -no-opengl -no-egl
      -no-sm -no-libudev -no-feature-gssapi -no-feature-vulkan"
    ;;
  windows) qt_config="$qt_config -static-runtime -no-freetype" ;;
esac

# Runs Qt's configure / qt-configure-module: the .bat through cmd.exe on Windows.
qt_configure() { # <script without extension> <args...>
  script=$1
  shift
  if [ "$platform" = windows ]; then
    MSYS2_ARG_CONV_EXCL='*' cmd.exe /c "$(cygpath -w "$script.bat")" "$@"
  else
    "$script" "$@"
  fi
}

step "qtbase $QT_VERSION (static)"
mkdir -p "$work/qt-build/qtbase"
(
  cd "$work/qt-build/qtbase"
  # shellcheck disable=SC2086 # word splitting of the option lists is intended
  qt_configure "$src/qtbase-everywhere-src-$QT_VERSION/configure" -prefix "$(native "$qt_prefix")" \
    $qt_config -- $cmake_args
  cmake --build . --parallel "$jobs"
  cmake --install .
)

# Modules on top of qtbase: QtQml (QJSEngine), QtUiTools and lrelease (qttools), Core5Compat.
# Quick is not built: it needs qtshadertools, which is left out.
module() {
  name=$1
  shift
  step "$name $QT_VERSION (static)"
  mkdir -p "$work/qt-build/$name"
  (
    cd "$work/qt-build/$name"
    # shellcheck disable=SC2086
    qt_configure "$qt_prefix/bin/qt-configure-module" "$(native "$src/$name-everywhere-src-$QT_VERSION")" \
      -- $cmake_args "$@"
    cmake --build . --parallel "$jobs"
    cmake --install .
  )
}
module qtdeclarative -DFEATURE_qml_debug=OFF
module qttools -DFEATURE_assistant=OFF -DFEATURE_designer=OFF -DFEATURE_pixeltool=OFF \
  -DFEATURE_distancefieldgenerator=OFF -DFEATURE_qdoc=OFF -DFEATURE_clang=OFF -DFEATURE_clangcpp=OFF \
  -DFEATURE_qdbus=OFF -DFEATURE_qtdiag=OFF -DFEATURE_qev=OFF -DFEATURE_kmap2qmap=OFF \
  -DFEATURE_qtplugininfo=OFF -DFEATURE_qtattributionsscanner=OFF
module qt5compat

step "Qt Installer Framework $IFW_VERSION"
# The 4.11.0 tarball unpacks into installer-framework-everywhere-src-dev/.
ifw_src=""
for d in "$src"/installer-framework-everywhere-src-*; do
  [ -f "$d/installerfw.pro" ] && ifw_src=$d
done
[ -n "$ifw_src" ] || fail "installerfw.pro not found in $src"
ifw_build=$work/ifw-build
rm -rf "$ifw_build"
mkdir -p "$ifw_build"
qmake_args="CONFIG+=release INCLUDEPATH+=$(native "$xz_prefix/include") IFW_LZMA_LIBRARY=$(native "$lzma_lib")"
case "$platform" in
  macos)
    qmake_args="$qmake_args QMAKE_MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET QMAKE_APPLE_DEVICE_ARCHS=arm64"
    ;;
  linux)
    qmake_args="$qmake_args INCLUDEPATH+=$bz_prefix/include IFW_BZIP2_LIBRARY=$bz_lib"
    ;;
  windows)
    # liblzma is static: without LZMA_API_STATIC its header declares dllimport functions.
    qmake_args="$qmake_args INCLUDEPATH+=$(native "$bz_prefix/include") IFW_BZIP2_LIBRARY=$(native "$bz_lib")
      INCLUDEPATH+=$(native "$zlib_prefix/include") IFW_ZLIB_LIBRARY=$(native "$zlib_lib") DEFINES+=LZMA_API_STATIC"
    ;;
esac
(
  cd "$ifw_build"
  # shellcheck disable=SC2086
  "$qt_prefix/bin/qmake$exe" -r "$(native "$ifw_src/installerfw.pro")" $qmake_args
  if [ "$platform" = windows ]; then
    "$work/jom/jom.exe" -j "$jobs"
  else
    make -j"$jobs"
  fi
)

step "install into $prefix and check"
rm -rf "$prefix/bin" "$prefix/licenses"
mkdir -p "$prefix/bin"
for tool in binarycreator installerbase archivegen repogen devtool; do
  bin="$ifw_build/bin/$tool$exe"
  [ -f "$bin" ] || fail "not built: $bin"
  cp "$bin" "$prefix/bin/$tool$exe"
  out="$prefix/bin/$tool$exe"
  case "$platform" in
    macos)
      archs=$(lipo -archs "$out")
      [ "$archs" = arm64 ] || fail "$tool is not arm64-only: $archs"
      # Only system libraries and frameworks: the installer must run on a plain Mac.
      for lib in $(otool -L "$out" | tail -n +2 | awk '{print $1}'); do
        case "$lib" in
          /usr/lib/* | /System/Library/*) ;;
          *) fail "$tool links to a non-system library: $lib" ;;
        esac
      done
      ;;
    linux)
      # Qt, liblzma and libbz2 are linked in; what is left are the system libraries of a desktop.
      # Direct dependencies only (ldd also lists e.g. FreeType's own libbz2).
      needed=$(readelf -d "$out" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
      echo "$needed" | sed 's/^/  /'
      if echo "$needed" | grep -E 'libQt|liblzma|libbz2'; then
        fail "$tool links to a library that should be static"
      fi
      if ldd "$out" | grep 'not found'; then
        fail "$tool needs a library that is not installed"
      fi
      ;;
    windows)
      # Static Qt and static MSVC runtime: only Windows system DLLs.
      deps=$(dumpbin.exe -nologo -dependents "$(native "$out")" | tr -d '\r' | awk '/\.dll$/ {print $1}')
      echo "$deps" | sed 's/^/  /'
      if echo "$deps" | grep -iE '^(qt|msvcp|vcruntime|liblzma|libbz2)'; then
        fail "$tool links to a library that should be static"
      fi
      ;;
  esac
done

# Licenses of what is in the binaries (the README lists the sources).
lic=$prefix/licenses
mkdir -p "$lic/qt-installer-framework" "$lic/qt" "$lic/xz"
cp "$ifw_src"/LICENSES/*.txt "$lic/qt-installer-framework/"
for m in qtbase qtdeclarative qttools qt5compat; do
  cp "$src/$m-everywhere-src-$QT_VERSION"/LICENSES/*.txt "$lic/qt/"
done
cp "$src/xz-$XZ_VERSION/COPYING" "$src/xz-$XZ_VERSION/COPYING.0BSD" "$lic/xz/"
if [ "$platform" != macos ]; then
  mkdir -p "$lic/bzip2"
  cp "$src/bzip2-$BZIP2_VERSION/LICENSE" "$lic/bzip2/"
fi
if [ "$platform" = windows ]; then
  mkdir -p "$lic/zlib"
  cp "$src/zlib-$ZLIB_VERSION/LICENSE" "$lic/zlib/"
fi

{
  printf 'ifw=%s\nqt=%s\nxz=%s\n' "$IFW_VERSION" "$QT_VERSION" "$XZ_VERSION"
  [ "$platform" != macos ] && printf 'bzip2=%s\n' "$BZIP2_VERSION"
  [ "$platform" = windows ] && printf 'zlib=%s\n' "$ZLIB_VERSION"
  printf 'platform=%s-%s\n' "$platform" "$arch"
} > "$prefix/VERSIONS"
step "done"
