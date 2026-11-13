# qt-ifw-asset

Prebuilt [Qt Installer Framework](https://doc.qt.io/qtinstallerframework/) (IFW) tools, built once against a
static Qt and published to Maven Central, so CI jobs that make installers download them instead of compiling Qt
and IFW on every run.

| | |
|---|---|
| Coordinates | `eu.virtualparadox:qt-ifw:4.11.0-qt6.9.3-1` |
| macOS arm64 | classifier `macos-aarch64`, type `tar.gz` |
| Linux x86_64 | classifier `linux-x86_64`, type `tar.gz` |
| Windows x86_64 | classifier `windows-x86_64`, type `zip` |

The version is `<IFW version>-qt<Qt version>-<build number>`. Releases on Central cannot be replaced or
deleted; the build number is raised to republish the same IFW and Qt versions (for example with a fixed build).

## What is in the archive

```
bin/        binarycreator, installerbase, archivegen, repogen, devtool (.exe on Windows)
licenses/   licenses of everything linked in: qt-installer-framework/, qt/, xz/, bzip2/ (Linux, Windows),
            zlib/ (Windows)
VERSIONS    ifw=, qt=, xz=, bzip2=, zlib= and platform=
README.txt  this summary and where the sources are
```

The files are at the archive root, so it unpacks straight into the target folder (`<dir>/bin/binarycreator`).

- Qt 6.9.3 is linked statically (qtbase, qtdeclarative for QtQml, qttools for QtUiTools, qt5compat), with its
  bundled zlib, libpng, libjpeg, PCRE2, HarfBuzz and double-conversion; no ICU, OpenSSL, D-Bus or SQL.
- liblzma (xz 5.8.1) is linked statically everywhere, libbz2 (bzip2 1.0.8) on Linux and Windows, zlib 1.3.1 on
  Windows; macOS uses the system `libbz2`, `libz` and `libiconv`, Linux the system `libz`.
- **macOS**: arm64 only, macOS 12 or later; links only to `/usr/lib` and system frameworks.
- **Windows**: static MSVC runtime; links only to Windows system DLLs.
- **Linux**: built on Ubuntu 24.04 (glibc 2.39); uses the desktop's X11/xcb, xkbcommon, fontconfig and FreeType
  libraries (installer GUI). OpenGL is not used.

## Use with Maven

Download the archive for one platform (for example in CI):

```
mvn dependency:copy -Dartifact=eu.virtualparadox:qt-ifw:4.11.0-qt6.9.3-1:tar.gz:macos-aarch64 -DoutputDirectory=target
tar -xzf target/qt-ifw-4.11.0-qt6.9.3-1-macos-aarch64.tar.gz -C .tools/ifw
.tools/ifw/bin/binarycreator --help
```

Windows: `-Dartifact=eu.virtualparadox:qt-ifw:4.11.0-qt6.9.3-1:zip:windows-x86_64`, then `unzip`.

Or in a pom, with `maven-dependency-plugin`:

```xml
<artifactItem>
  <groupId>eu.virtualparadox</groupId>
  <artifactId>qt-ifw</artifactId>
  <version>4.11.0-qt6.9.3-1</version>
  <type>tar.gz</type>                  <!-- zip for windows-x86_64 -->
  <classifier>macos-aarch64</classifier>
</artifactItem>
```

`dependency:copy` and unpacking with `tar`/`unzip` keep the executable bits; `dependency:unpack` may not restore
them, so `chmod +x bin/*` after it on macOS and Linux.

Maven Central needs no credentials.

## How it is built

`build/build-ifw.sh <prefix>` builds everything from the upstream source archives, which it downloads and checks
against pinned SHA-256 sums:

1. xz (liblzma), on Linux and Windows bzip2 (libbz2), and on Windows zlib as static libraries;
2. static Qt: qtbase with the options IFW's `INSTALL` recommends for the platform, then qtdeclarative, qttools and
   qt5compat;
3. IFW with qmake against that Qt;
4. checks the result (macOS: arm64 only and only system libraries; Linux: `readelf -d`, no Qt, liblzma or libbz2;
   Windows: `dumpbin /dependents`),
   and copies the licenses.

`build/package-ifw.sh <prefix> <archive>` packs it; `build/smoke-test.sh <prefix>` runs `binarycreator --help`
and `installerbase --version` (the IFW and Qt versions, and libarchive with liblzma and bzip2), checks
`lipo -archs` = `arm64` on macOS, builds a one-component offline installer and installs it headlessly.

Locally (about 30-60 minutes):

- macOS arm64: Xcode command line tools.
- Linux x86_64: `sudo apt-get install $(cat build/linux-packages.txt)` (Ubuntu/Debian).
- Windows x86_64: Visual Studio 2022 (C++), Ninja and Git Bash; run from Git Bash started inside an
  "x64 Native Tools" prompt, with a short `IFW_BUILD_DIR` such as `C:/w`.

```
build/build-ifw.sh target/ifw
build/smoke-test.sh target/ifw
```

## Release (CI)

`.github/workflows/release.yml` runs only by hand (Actions > release > Run workflow, or
`gh workflow run release.yml -f publish=true`). It builds on `macos-15` (arm64), `ubuntu-latest` and
`windows-latest`, packs and smoke-tests the unpacked archive on each, then publishes the three archives in one
Central Portal deployment (`mvn deploy`, signed with GPG, published automatically) and waits until
`repo1.maven.org` serves all three. With `publish` off it builds and tests only. It stops early if the version is
already on Central.

Secrets (organization secrets of `virtualparadoxorg`, or repository secrets with the same names):
`CENTRAL_TOKEN_ID`, `CENTRAL_TOKEN_PASSWORD` (Central Portal user token for the `eu.virtualparadox` namespace),
`GPG_PRIVATE_KEY` (ASCII-armored signing key, published on a key server), `GPG_PASSPHRASE`.

### A new IFW or Qt version

1. In `build/build-ifw.sh`, set `IFW_VERSION` / `QT_VERSION` (and the other pinned versions if needed) and the
   SHA-256 of each changed archive (`sha256sum` of the downloaded file; Qt publishes `.sha256` files next to its
   archives).
2. Check the Qt configure options against IFW's `INSTALL` file for that version.
3. In `pom.xml`, set the version to `<IFW>-qt<Qt>-1`, update the description, and update this README.
4. Open a pull request, run the workflow on its branch with `publish` off, merge, then run it on `main` with
   `publish` on.

To republish the same versions (for example a build fix), raise only the last number of the version.

## Licenses

- The build scripts in this repository: MIT (`LICENSE`).
- The published binaries: the Qt Installer Framework is licensed under the GNU GPL v3 with the Qt GPL exception
  1.0; Qt under the GNU LGPL v3 (or GPL v2/v3); xz's liblzma is 0BSD; bzip2 under its BSD-style license; zlib under
  the zlib license. The
  license texts are in the archive's `licenses/` folder. Installers created with these tools are covered by the
  Qt GPL exception.
- Corresponding source: this repository's build script with the unmodified upstream archives it downloads:
  [Qt Installer Framework](https://download.qt.io/official_releases/qt-installer-framework/),
  [Qt](https://download.qt.io/archive/qt/), [xz](https://github.com/tukaani-project/xz/releases),
  [bzip2](https://sourceware.org/pub/bzip2/), [zlib](https://github.com/madler/zlib/releases).
